#!/usr/bin/env bash
# Dựng trạng thái BÌNH THƯỜNG: VIP 172.28.5.100 nằm trên node-a (MASTER),
# client đã gọi VIP và học được MAC của node-a vào bảng ARP.
# Chạy lại script này bất cứ lúc nào để reset sạch lab về trạng thái ban đầu.
set -e
VIP=172.28.5.100

echo "🔧 Đang dựng trạng thái bình thường (VIP $VIP → node-a)..."

# Reset sạch dấu vết của lần demo trước
docker compose start node-a >/dev/null 2>&1 || true

# Chờ node-a thật sự nhận lệnh được (poll thay vì sleep cứng — máy chậm vẫn chạy đúng)
for _ in $(seq 30); do
  docker compose exec node-a ip -o link show eth0 >/dev/null 2>&1 && break
  sleep 1
done

docker compose exec node-b ip addr del $VIP/24 dev eth0 2>/dev/null || true
docker compose exec node-a ip addr replace $VIP/24 dev eth0
docker compose exec client ip neigh flush dev eth0

# Client gọi VIP lần đầu -> học MAC của node-a vào bảng ARP
docker compose exec client curl -s --max-time 3 http://$VIP | head -1

echo "✅ Xong. Client đang phục vụ bởi node-a, bảng ARP đã học MAC của node-a:"
docker compose exec client ip neigh show | grep $VIP
