#!/bin/bash
# Script by NguyenLP - IPv6 Proxy Manager with Squid integration

WORKDIR="/etc/nlpipv6/"
WORKDATA="${WORKDIR}/proxy_data.txt"
PROXY_FILE="${WORKDIR}/proxy.txt"
SQUID_CONF="/etc/squid/squid.conf"
LOGFILE="/var/log/nlpipv6.log"

# Create working directory
mkdir -p "$WORKDIR"

# Detect network interface
network_card=$(ip -o link show | awk '{print $2,$9}' | grep -E 'ens|enp|eno' | cut -d: -f1)
if [[ -z "$network_card" ]]; then
    network_card="eth0"
fi

# Get LAN IPv4 address
LAN_IP=$(ip -4 addr show "$network_card" | grep "inet" | awk '{print $2}' | cut -d/ -f1)

# --- Check Dependencies ---
check_dependencies() {
    for cmd in ip openssl squid systemctl htpasswd; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: $cmd not found. Please install it."
            exit 1
        fi
    done
    if ! command -v squid-mime-data &> /dev/null; then
        echo "Error: squid-mime-data not found. Installing squid..."
        if ! dnf install squid -y; then
            echo "Error: Failed to install squid. Please install manually."
            exit 1
        fi
    fi
}

# --- Squid functions ---

# Backup current squid.conf before modifying it
backup_squid_config() {
    if [[ -f "$SQUID_CONF" ]]; then
        cp "$SQUID_CONF" "${SQUID_CONF}.bak"
        echo "Backup of squid.conf created at ${SQUID_CONF}.bak"
    fi
}

# Generate Squid config with proper ACL and Proxy setup
generate_squid_config() {
    backup_squid_config

    cat > "$SQUID_CONF" <<-EOF
http_port $LAN_IP:3128 transparent

acl localnet src 127.0.0.1/32
acl localnet src ::1/128
acl mynetwork src 192.168.1.0/24 # Thay đổi nếu cần
http_access allow localnet
http_access allow mynetwork
http_access deny all

forwarded_for off
via off
never_direct allow all

# IPv6 routing
cache_peer 127.0.0.1 parent 80 0 no-query default name=ipv6-out
cache_peer_access ipv6-out allow mynetwork

EOF

    if [[ -f "$WORKDATA" ]]; then
        while IFS=: read -r user pass ip port ipv6; do
            if [[ "$pass" == "noauth" ]]; then
                cat >> "$SQUID_CONF" <<-EOF
acl proxy_$port myportname $port
acl ipv6_$ipv6 myipname $ipv6
http_access allow proxy_$port ipv6_$ipv6
EOF
            else
                cat >> "$SQUID_CONF" <<-EOF
auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm NguyenLP Proxy
acl authenticated proxy_auth REQUIRED
acl proxy_$port myportname $port
acl ipv6_$ipv6 myipname $ipv6
http_access allow proxy_$port ipv6_$ipv6 authenticated
EOF
            fi
        done < "$WORKDATA"
    fi
}

# Restart Squid to apply new config
restart_squid() {
    if ! systemctl restart squid; then
        echo "Error: Failed to restart Squid. Check logs: journalctl -xe"
        return 1
    fi
}

# --- IPv6 functions ---

# Enable or disable IPv6 on system
toggle_ipv6() {
    inet6=$(ip a | grep inet6)
    if [[ $inet6 ]]; then
        read -r -p "IPv6 is ENABLED. Do you want to disable it? (Y/n) " disable
        if [[ "$disable" =~ ^[Yy]$ ]]; then
            sysctl -w net.ipv6.conf.all.disable_ipv6=1
            echo "IPv6 has been DISABLED."
        fi
    else
        read -r -p "IPv6 is DISABLED. Do you want to enable it? (Y/n) " enable
        if [[ "$enable" =~ ^[Yy]$ ]]; then
            sysctl -w net.ipv6.conf.all.disable_ipv6=0
            echo "IPv6 has been ENABLED."
        fi
    fi
}

# List all IPv6 addresses
list_ipv6() {
    ip -6 addr show dev "$network_card" | grep inet6 | awk '{print $2}'
}

# Add random IPv6 address to system
add_random_ipv6() {
    read -r -p "Enter IPv6 prefix (e.g., 2405:4803:d732:3630): " prefix
    read -r -p "Enter subnet mask (e.g., 64): " mask

    # Validate IPv6 prefix
    if ! [[ "$prefix" =~ ^[0-9a-fA-F:]+$ ]]; then
        echo "Invalid IPv6 prefix. Please try again."
        return
    fi

    random_suffix=$(openssl rand -hex 8 | sed 's/../&:/g' | sed 's/:$//')
    ipv6="${prefix}:${random_suffix}/${mask}"
    sudo ip -6 addr add "$ipv6" dev "$network_card"
    echo "Added IPv6: $ipv6"
}

# --- Proxy functions ---

# Add new proxy to Squid config
add_proxy() {
    read -r -p "Enter number of proxies to create: " count
    read -r -p "Enter starting port (e.g., 22000): " start_port
    read -r -p "Enter IPv6 prefix (e.g., 2405:4803:d732:3630): " prefix

    # Validate port
    if ! [[ "$start_port" =~ ^[0-9]+$ ]] || [ "$start_port" -lt 1024 ] || [ "$start_port" -gt 65535 ]; then
        echo "Invalid port number. Please enter a value between 1024 and 65535."
        return
    fi

    user="proxyuser"
    > "$PROXY_FILE"

    for ((i = 0; i < count; i++)); do
        port=$((start_port + i))
        random_suffix=$(openssl rand -hex 8 | sed 's/../&:/g' | sed 's/:$//')
        ipv6="${prefix}:${random_suffix}/64"
        sudo ip -6 addr add "$ipv6" dev "$network_card"
        echo "$user:noauth:$LAN_IP:$port:$ipv6" >> "$WORKDATA"
        echo "$LAN_IP:$port" >> "$PROXY_FILE"
        echo "Added proxy: Port $port -> $ipv6 (LAN IP: $LAN_IP)"
    done

    generate_squid_config
    restart_squid
}

# List active proxies
list_proxies() {
    if [[ -f "$WORKDATA" ]]; then
        echo "Active proxies:"
        cat "$WORKDATA"
    else
        echo "No proxies found."
    fi
}

# Delete all proxies
delete_proxies() {
    if [[ -f "$WORKDATA" ]]; then
        while IFS=: read -r user pass ip port ipv6; do
            sudo ip -6 addr del "$ipv6" dev "$network_card"
        done < "$WORKDATA"
        rm -f "$WORKDATA"
        > "$PROXY_FILE" # Clear proxy.txt as well
        echo "All proxies deleted."
    else
        echo "No proxies to delete."
    fi
    generate_squid_config
    restart_squid
}

# Enable/Disable proxy authentication
toggle_proxy_auth() {
    if grep -q "auth_param basic" "$SQUID_CONF"; then
        # Disable authentication
        sed -i '/auth_param basic/d' "$SQUID_CONF"
        sed -i '/acl authenticated/d' "$SQUID_CONF"
        sed -i '/http_access allow authenticated/d' "$SQUID_CONF"
        rm -f /etc/squid/passwd
        echo "Proxy authentication disabled."
    else
        # Enable authentication
        user=$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)
        htpasswd -b -c /etc/squid/passwd "$user" "randompassword"
        echo "Proxy authentication enabled. Username: $user, Password: randompassword"
    fi
    restart_squid
}

# --- Main menu ---
menu() {
    clear
    echo "==================== IPv6 Proxy Manager ===================="
    echo "1) Add Proxy"
    echo "2) List Proxies"
    echo "3) Delete Proxies"
    echo "4) Enable/Disable IPv6"
    echo "5) Toggle Proxy Authentication"
    echo "6) Exit"
    echo "============================================================="
    read -p "Choose an option: " option

    case "$option" in
        1) add_proxy ;;
        2) list_proxies ;;
        3) delete_proxies ;;
        4) toggle_ipv6 ;;
        5) toggle_proxy_auth ;;
        6) exit 0 ;;
        *) echo "Invalid option. Please try again." && sleep 2 && menu ;;
    esac
}

# Run the script
check_dependencies
menu
