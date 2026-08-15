#!/usr/bin/env bash
# Chữa bệnh: Chuyển Nginx sang sử dụng fullchain.crt (đầy đủ Server + Intermediate CA)
set -e
echo "🩺 Đang khắc phục sự cố (Fixing): Cấu hình Nginx sử dụng fullchain.crt..."
# Ghi vào nginx/nginx.conf (đã gitignore) — không làm bẩn cây git
cp nginx/conf/good.conf nginx/nginx.conf
# Restart de doc lai config moi tu mount (reload co the doc file mount cu tren Docker Desktop)
 docker compose restart web-server >/dev/null
echo "✅ Đã khắc phục lỗi thành công!"
echo "👉 Hiện tượng: Mọi thiết bị (kể cả điện thoại/curl) đều nhận diện được chuỗi Trust Chain hợp lệ."
