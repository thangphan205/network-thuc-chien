#!/usr/bin/env bash
# Kích hoạt lỗi: Nginx chỉ lắng nghe trên 127.0.0.1
set -e
cd "$(dirname "$0")/.."
echo "🚨 Đang cấu hình Nginx chỉ lắng nghe trên 127.0.0.1 (Loopback)..."
# Ghi vào nginx/nginx.conf (đã gitignore) — không làm bẩn cây git
cp nginx/conf/bad.conf nginx/nginx.conf
# Đổi địa chỉ listen (0.0.0.0 -> 127.0.0.1) cần restart hẳn: `nginx -s reload` giữ lại
# socket wildcard cũ nên không narrow được bind — restart để bind lại từ đầu.
docker compose restart web-server >/dev/null
echo "✅ Đã kích hoạt lỗi Bind 127.0.0.1!"
echo "👉 Hiện tượng: Đứng trong server thì curl 127.0.0.1 được, nhưng từ máy khác (client/laptop) gọi vào IP server thì bị Connection Refused."
