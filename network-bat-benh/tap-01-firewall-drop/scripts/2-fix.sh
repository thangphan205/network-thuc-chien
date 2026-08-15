#!/usr/bin/env bash
# Chữa bệnh: Xóa luật chặn DROP port 80
echo "🩺 Đang khắc phục sự cố (Fixing): Xóa luật chặn iptables trên Web Server..."
docker compose exec web-server iptables -F
echo "✅ Đã khắc phục lỗi thành công!"
echo "👉 Hiện tượng: Ping OK và Web (HTTP:80) phản hồi HTTP/1.1 200 OK."
