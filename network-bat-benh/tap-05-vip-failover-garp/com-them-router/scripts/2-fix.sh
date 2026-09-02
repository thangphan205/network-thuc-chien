#!/usr/bin/env bash
# Chữa bệnh: vẫn ĐÚNG MỘT LỆNH đó, ở đúng chỗ đó — trên node-b.
# GARP là broadcast trong subnet server, mà router có chân trong subnet đó
# -> router nhận được và tự cập nhật. Không cần SSH vào router.
set -e
cd "$(dirname "$0")/.."
source scripts/_lib.sh
SRV_IF=$(r_srv_if)

echo "🩺 node-b phát Gratuitous ARP cho $VIP..."
echo "   Lệnh: arping -U -c 3 -I eth0 $VIP"
docker compose exec node-b arping -U -c 3 -I eth0 $VIP

echo ""
echo "✅ Bảng ARP của ROUTER (không hề SSH vào router, không chạm vào client):"
docker compose exec router ip neigh show dev "$SRV_IF" | grep $VIP | sed 's/^/   /'
echo "👉 Router đã tự cập nhật sang MAC node-b. Chạy ./scripts/test.sh để xác nhận."
