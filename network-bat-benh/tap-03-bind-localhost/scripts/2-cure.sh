#!/usr/bin/env bash
# Chữa bệnh: Chuyển Nginx sang lắng nghe 0.0.0.0 (tất cả card mạng)
echo "🩺 Đang chữa bệnh: Cấu hình Nginx lắng nghe trên 0.0.0.0:80..."
cat << 'EOF' > nginx/nginx.conf
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}
EOF
docker compose exec web-server nginx -s reload 2>/dev/null || docker compose restart web-server
echo "✅ Đã chữa khỏi lỗi!"
echo "👉 Hiện tượng: Máy ngoài gọi vào IP server đã nhận HTTP 200 OK."
