#!/usr/bin/env bash
# Kích hoạt lỗi: Chứng chỉ SSL hết hạn / Lệch giờ hệ thống
echo "🚨 Đang kích hoạt lỗi: Sử dụng chứng chỉ TLS không hợp lệ / Hết hạn..."
cat << 'EOF' > nginx/nginx.conf
server {
    listen 443 ssl;
    server_name secure.local;

    ssl_certificate /etc/nginx/ssl/expired.crt;
    ssl_certificate_key /etc/nginx/ssl/expired.key;

    location / {
        return 200 "CA BENH 07: KET NOI HTTPS THANH CONG (TLS OK)!\n";
        add_header Content-Type text/plain;
    }
}
EOF
docker compose exec web-server nginx -s reload 2>/dev/null || docker compose restart web-server
echo "✅ Đã kích hoạt lỗi TLS Certificate!"
echo "👉 Hiện tượng: Ping OK, TCP 443 OK, nhưng khi bắt tay TLS thì Client báo lỗi Certificate Invalid / Expired."
