#!/bin/bash
# Script to download and install nlpipv6.sh

# URL của file trên GitHub (dạng raw)
GITHUB_URL="https://raw.githubusercontent.com/nguyenlpp/nguyenlpipv6/main/nlpipv6.sh"

# Đường dẫn lưu file
INSTALL_PATH="/usr/local/bin/nlpipv6"

echo "Đang tải script từ GitHub..."
if curl -fsSL "$GITHUB_URL" -o "$INSTALL_PATH"; then
    echo "Tải thành công. Lưu vào $INSTALL_PATH"
else
    echo "Lỗi khi tải script. Vui lòng kiểm tra URL hoặc kết nối mạng."
    exit 1
fi

# Gán quyền thực thi cho file
chmod +x "$INSTALL_PATH"
echo "Gán quyền thực thi cho $INSTALL_PATH"

# Xác minh cài đặt
if [[ -f "$INSTALL_PATH" && -x "$INSTALL_PATH" ]]; then
    echo "Cài đặt thành công. Bạn có thể gọi script bằng cách gõ 'nlpipv6'."
else
    echo "Cài đặt thất bại. Vui lòng kiểm tra thủ công."
fi
