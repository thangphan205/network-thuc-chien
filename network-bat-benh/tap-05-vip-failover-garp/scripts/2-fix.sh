#!/usr/bin/env bash
# Chữa bệnh: node-b phát Gratuitous ARP để cả LAN cập nhật lại MAC cho VIP.
# Điểm mấu chốt: KHÔNG đụng một ngón tay nào vào client. Đúng cách làm thực tế —
# bên failover có trách nhiệm thông báo, không phải bắt admin chạy quanh flush ARP từng máy.
set -e
VIP=172.28.5.100

echo "🩺 Đang khắc phục sự cố (Fixing): node-b phát Gratuitous ARP cho $VIP..."
echo "   Lệnh: arping -U -c 3 -I eth0 $VIP   (-U = Unsolicited ARP, broadcast ra toàn LAN)"
docker compose exec node-b arping -U -c 3 -I eth0 $VIP

echo ""
echo "✅ Đã phát GARP! Bảng ARP của client (không hề chạm vào client):"
docker compose exec client ip neigh show | grep $VIP
echo "👉 Client đã tự cập nhật sang MAC của node-b. Chạy ./scripts/test.sh để xác nhận."
