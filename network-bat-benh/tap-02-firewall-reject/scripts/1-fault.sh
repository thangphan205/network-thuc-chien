#!/usr/bin/env bash
# Kích hoạt lỗi: Firewall Active REJECT với TCP Reset
echo "🚨 Đang kích hoạt lỗi: Firewall REJECT Port 80 (TCP RST)..."
docker compose exec web-server iptables -F
docker compose exec web-server iptables -I INPUT -p tcp --dport 80 -j REJECT --reject-with tcp-reset
echo "✅ Đã kích hoạt lỗi REJECT thành công!"
echo "👉 Hiện tượng: Ping vẫn phản hồi 100%, nhưng Web báo lỗi 'Connection refused' ngay lập tức (TCP RST)."
