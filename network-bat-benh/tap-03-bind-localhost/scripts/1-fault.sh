#!/usr/bin/env bash
# Kích hoạt lỗi: Nginx chỉ lắng nghe trên 127.0.0.1
echo "🚨 Đang cấu hình Nginx chỉ lắng nghe trên 127.0.0.1 (Loopback)..."
cat << 'EOF' > nginx/nginx.conf
server {
    listen 127.0.0.1:80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}
EOF
docker compose exec web-server nginx -s reload 2>/dev/null || docker compose restart web-server
echo "✅ Đã kích hoạt lỗi Bind 127.0.0.1!"
echo "👉 Hiện tượng: Đứng trong server thì curl 127.0.0.1 được, nhưng từ máy khác (client/laptop) gọi vào IP server thì bị Connection Refused."
