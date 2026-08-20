#!/usr/bin/env bash
# Chữa bệnh: Chuyển Nginx sang lắng nghe 0.0.0.0 (tất cả card mạng)
set -e
cd "$(dirname "$0")/.."
echo "🩺 Đang khắc phục sự cố (Fixing): Cấu hình Nginx lắng nghe trên 0.0.0.0:80..."
# Ghi vào nginx/nginx.conf (đã gitignore) — không làm bẩn cây git
cp nginx/conf/good.conf nginx/nginx.conf
# Restart để bind lại 0.0.0.0:80 (xem ghi chú trong 1-fault.sh)
docker compose restart web-server >/dev/null
echo "✅ Đã khắc phục lỗi thành công!"
echo "👉 Hiện tượng: Máy ngoài gọi vào IP server đã nhận HTTP 200 OK."
