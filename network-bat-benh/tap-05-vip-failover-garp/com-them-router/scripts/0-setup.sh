#!/usr/bin/env bash
# Dựng trạng thái BÌNH THƯỜNG cho lab có router:
#   VIP nằm trên node-a, client đã gọi VIP một lần qua router.
#   Điểm mấu chốt: ROUTER học MAC của node-a, còn CLIENT thì KHÔNG hề biết VIP là ai.
# Chạy lại bất cứ lúc nào để reset sạch lab.
set -e
cd "$(dirname "$0")/.."
source scripts/_lib.sh

echo "🔧 Đang dựng trạng thái bình thường (VIP $VIP → node-a, qua router)..."

docker compose start node-a >/dev/null 2>&1 || true
for _ in $(seq 30); do
  docker compose exec node-a ip -o link show eth0 >/dev/null 2>&1 && break
  sleep 1
done

# Gán VIP về đúng node-a
docker compose exec node-b ip addr del $VIP/24 dev eth0 2>/dev/null || true
docker compose exec node-a ip addr replace $VIP/24 dev eth0

# Định tuyến: client <-> server phải đi vòng qua router
docker compose exec client ip route replace $SERVER_NET via $R_CLIENT
docker compose exec node-a ip route replace $CLIENT_NET via $R_SERVER
docker compose exec node-b ip route replace $CLIENT_NET via $R_SERVER

# Xoá sạch dấu vết ARP của lần demo trước, ở CẢ client lẫn router
docker compose exec client ip neigh flush all
docker compose exec router ip neigh flush all

# Client gọi VIP -> chính ROUTER là thằng đi ARP hỏi VIP và học MAC node-a
docker compose exec client curl -s --max-time 5 http://$VIP | head -1

SRV_IF=$(r_srv_if)
echo ""
echo "✅ Xong. Soi hai bảng ARP để thấy ai đang giữ thông tin gì:"
echo ""
echo "   [CLIENT] — KHÔNG hề có dòng nào cho VIP $VIP, chỉ biết mỗi router:"
docker compose exec client ip neigh show | sed 's/^/     /'
echo ""
echo "   [ROUTER] interface phía server ($SRV_IF) — đây mới là thằng ôm MAC của VIP:"
docker compose exec router ip neigh show dev "$SRV_IF" | sed 's/^/     /'
