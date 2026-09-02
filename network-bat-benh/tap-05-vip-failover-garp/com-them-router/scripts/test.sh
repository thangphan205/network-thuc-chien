#!/usr/bin/env bash
# Chẩn đoán ca bệnh khi có ROUTER đứng giữa.
# Trình tự cố ý: soi CLIENT trước (sạch trơn), rồi mới soi ROUTER (ổ bệnh).
cd "$(dirname "$0")/.."
source scripts/_lib.sh
SRV_IF=$(r_srv_if)

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
echo "🩺 [BƯỚC 2] Bảng ARP trên CLIENT:"
echo "=========================================="
docker compose exec client ip neigh show
echo "👉 KHÔNG có dòng nào cho $VIP — và sẽ KHÔNG BAO GIỜ có."
echo "   Client khác subnet nên nó chỉ ARP hỏi router. Client hoàn toàn VÔ CAN."
echo "   Mọi nỗ lực debug ở client là ngõ cụt."

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Bảng ARP trên ROUTER (chân $SRV_IF, phía server):"
echo "=========================================="
docker compose exec router ip neigh show dev "$SRV_IF"
echo "👉 Ổ BỆNH Ở ĐÂY. So MAC dòng $VIP với 2 MAC ở BƯỚC 1."

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 4] Client gọi VIP:"
echo "=========================================="
docker compose exec client ping -c 3 -W 1 $VIP
echo -n "curl: "
docker compose exec client curl -s --max-time 3 http://$VIP \
  || echo "❌ Không gọi được dịch vụ qua VIP!"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 5] Chiều NGƯỢC LẠI: node-b gọi client:"
echo "=========================================="
docker compose exec node-b ping -c 2 -W 1 172.28.6.20
echo "👉 Chiều RA thông, chiều VÀO chết. Đứt MỘT CHIỀU — dấu vân tay của ca bệnh này."
echo "   SSH vào node-b test kiểu gì cũng thấy xanh, càng khó nghi ngờ."

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 6] traceroute từ client:"
echo "=========================================="
docker compose exec client traceroute -w 1 -q 1 -m 5 $VIP 2>&1
echo "👉 Qua được router rồi chết ngay sau đó = hỏng ở chặng L2 cuối cùng của router."
