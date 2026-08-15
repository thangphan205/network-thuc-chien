#!/usr/bin/env bash
# Chữa bệnh: Chuyển Nginx sang sử dụng fullchain.crt (đầy đủ Server + Intermediate CA)
echo "🩺 Đang chữa bệnh: Cấu hình Nginx sử dụng fullchain.crt..."
cat << 'EOF' > nginx/nginx.conf
server {
    listen 443 ssl;
    server_name app.chain.local;

    ssl_certificate /etc/nginx/ssl/fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    location / {
        return 200 "CA BENH 08: FULL CERTIFICATE CHAIN HOP LE (TLS OK)!\n";
        add_header Content-Type text/plain;
    }
}
EOF
docker compose exec web-server nginx -s reload 2>/dev/null || docker compose restart web-server
echo "✅ Đã chữa khỏi lỗi!"
echo "👉 Hiện tượng: Mọi thiết bị (kể cả điện thoại/curl) đều nhận diện được chuỗi Trust Chain hợp lệ."
