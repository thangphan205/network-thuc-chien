#!/usr/bin/env bash
# Kích hoạt lỗi: Nginx chỉ phục vụ Server Cert (thiếu Intermediate CA trong Chain)
echo "🚨 Đang kích hoạt lỗi: Cấu hình Nginx chỉ load server_only.crt (Thiếu Intermediate CA)..."
cat << 'EOF' > nginx/nginx.conf
server {
    listen 443 ssl;
    server_name app.chain.local;

    ssl_certificate /etc/nginx/ssl/server_only.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    location / {
        return 200 "CA BENH 08: FULL CERTIFICATE CHAIN HOP LE (TLS OK)!\n";
        add_header Content-Type text/plain;
    }
}
EOF
docker compose exec web-server nginx -s reload 2>/dev/null || docker compose restart web-server
echo "✅ Đã kích hoạt lỗi Incomplete Certificate Chain!"
echo "👉 Hiện tượng: Máy tính có cache Intermediate thì mở được, nhưng curl / mobile / API client sẽ báo lỗi 'unable to get local issuer certificate'."
