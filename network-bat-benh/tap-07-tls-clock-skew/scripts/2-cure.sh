#!/usr/bin/env bash
# Chữa bệnh: Dùng chứng chỉ TLS hợp lệ
echo "🩺 Đang chữa bệnh: Áp dụng chứng chỉ TLS hợp lệ..."
cat << 'EOF' > nginx/nginx.conf
server {
    listen 443 ssl;
    server_name secure.local;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    location / {
        return 200 "CA BENH 07: KET NOI HTTPS THANH CONG (TLS OK)!\n";
        add_header Content-Type text/plain;
    }
}
EOF
docker compose exec web-server nginx -s reload 2>/dev/null || docker compose restart web-server
echo "✅ Đã chữa khỏi lỗi!"
echo "👉 Hiện tượng: Bắt tay TLS Handshake thành công và nhận dữ liệu an toàn."
