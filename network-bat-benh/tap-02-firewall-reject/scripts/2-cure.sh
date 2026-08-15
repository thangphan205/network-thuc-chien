#!/usr/bin/env bash
# Chữa bệnh: Xóa bỏ luật REJECT
echo "🩺 Đang chữa bệnh: Xóa luật REJECT trên Web Server..."
docker compose exec web-server iptables -F
echo "✅ Đã chữa khỏi lỗi!"
echo "👉 Hiện tượng: Ping OK và Web phản hồi HTTP/1.1 200 OK."
