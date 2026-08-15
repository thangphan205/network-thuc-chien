#!/usr/bin/env bash
# Kích hoạt lỗi: Chứng chỉ SSL hết hạn
set -e
echo "🚨 Đang kích hoạt lỗi: Sử dụng chứng chỉ TLS đã hết hạn (notAfter=01/01/2024)..."
# Ghi vào nginx/nginx.conf (đã gitignore) — không làm bẩn cây git
cp nginx/conf/expired.conf nginx/nginx.conf
# Restart de doc lai config moi tu mount (reload co the doc file mount cu tren Docker Desktop)
 docker compose restart web-server >/dev/null
echo "✅ Đã kích hoạt lỗi TLS Certificate!"
echo "👉 Hiện tượng: Ping OK, TCP 443 OK, nhưng khi bắt tay TLS thì Client báo lỗi Certificate Invalid / Expired."
