#!/usr/bin/env bash
# Kích hoạt lỗi: Nginx chỉ phục vụ Server Cert (thiếu Intermediate CA trong Chain)
set -e
echo "🚨 Đang kích hoạt lỗi: Cấu hình Nginx chỉ load server_only.crt (Thiếu Intermediate CA)..."
# Ghi vào nginx/nginx.conf (đã gitignore) — không làm bẩn cây git
cp nginx/conf/bad.conf nginx/nginx.conf
# Restart de doc lai config moi tu mount (reload co the doc file mount cu tren Docker Desktop)
 docker compose restart web-server >/dev/null
echo "✅ Đã kích hoạt lỗi Incomplete Certificate Chain!"
echo "👉 Hiện tượng: Máy tính có cache Intermediate thì mở được, nhưng curl / mobile / API client sẽ báo lỗi 'unable to get local issuer certificate'."
