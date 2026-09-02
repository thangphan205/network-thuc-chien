#!/usr/bin/env bash
# Chẩn đoán: so MAC thật của 2 node với MAC mà client đang ôm trong bảng ARP
VIP=172.28.5.100

echo "=========================================="
echo "🩺 [BƯỚC 1] MAC THỰC TẾ của 2 node:"
echo "=========================================="
echo -n "node-a (MASTER):  "
docker compose exec node-a ip -o link show eth0 2>/dev/null | grep -o 'ether [^ ]*' || echo "(node-a đang CHẾT — đúng kịch bản failover)"
echo -n "node-b (BACKUP):  "
docker compose exec node-b ip -o link show eth0 | grep -o 'ether [^ ]*'
echo -n "VIP $VIP hiện nằm trên: "
docker compose exec node-b ip -o addr show eth0 | grep -q "$VIP" && echo "node-b" || echo "node-a"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Bảng ARP trên Client (ip neigh):"
echo "=========================================="
docker compose exec client ip neigh show
echo "👉 So MAC ở dòng $VIP với 2 MAC ở BƯỚC 1. Client đang gửi frame cho ai?"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Ping VIP từ Client:"
echo "=========================================="
docker compose exec client ping -c 3 -W 1 $VIP

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 4] Gọi dịch vụ thật qua VIP (curl):"
echo "=========================================="
docker compose exec client curl -s --max-time 3 http://$VIP \
  || echo "❌ Không gọi được dịch vụ qua VIP — dù backup đã lên và nginx vẫn chạy!"
