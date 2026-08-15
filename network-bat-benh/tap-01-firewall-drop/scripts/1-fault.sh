#!/usr/bin/env bash
# Kích hoạt lỗi: Firewall Silent DROP Port 80
echo "🚨 Đang kích hoạt lỗi: Firewall DROP Port 80..."
docker compose exec web-server iptables -F
docker compose exec web-server iptables -I INPUT -p tcp --dport 80 -j DROP
echo "✅ Đã kích hoạt lỗi DROP thành công!"
echo "👉 Hiện tượng: Ping vẫn phản hồi 100%, nhưng Web sẽ bị xoay tròn và Timeout (TCP SYN Retransmission)."
