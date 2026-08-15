#!/usr/bin/env bash
# Chữa bệnh: Dùng chứng chỉ TLS còn hạn
set -e
echo "🩺 Đang khắc phục sự cố (Fixing): Áp dụng chứng chỉ TLS hợp lệ..."
# Ghi vào nginx/nginx.conf (đã gitignore) — không làm bẩn cây git
cp nginx/conf/good.conf nginx/nginx.conf
# Restart de doc lai config moi tu mount (reload co the doc file mount cu tren Docker Desktop)
 docker compose restart web-server >/dev/null
echo "✅ Đã khắc phục lỗi thành công!"
echo "👉 Hiện tượng: Bắt tay TLS Handshake thành công và nhận dữ liệu an toàn."
