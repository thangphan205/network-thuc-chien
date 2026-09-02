#!/usr/bin/env bash
# Đường CHỮA CHÁY: khi GARP bị thiết bị nuốt (DAI, port-security, router tắt
# gratuitous ARP) thì phải vào thẳng router xoá entry sai bằng tay.
# Đồng thời chứng minh: entry sai trên router là NGUYÊN NHÂN DUY NHẤT.
# Chạy sau 1-fault.sh.
set -e
cd "$(dirname "$0")/.."
source scripts/_lib.sh
SRV_IF=$(r_srv_if)

echo "🔸 [A] Router đang ôm ENTRY SAI (MAC của node-a đã chết):"
docker compose exec router ip neigh show dev "$SRV_IF" | grep $VIP | sed 's/^/     /'
echo "     curl từ client →"
docker compose exec client curl -s -S --max-time 5 http://$VIP 2>&1 | sed 's/^/     /'

echo ""
echo "🔸 [B] Xoá entry sai đó khỏi router — KHÔNG chạm gì vào node-b, KHÔNG phát GARP:"
echo "     Lệnh trên router:  ip neigh del $VIP dev $SRV_IF"
docker compose exec router ip neigh del $VIP dev "$SRV_IF" 2>/dev/null || true
echo "     curl từ client →"
docker compose exec client curl -s -S --max-time 5 http://$VIP 2>&1 | sed 's/^/     /'
echo ""
docker compose exec router ip neigh show dev "$SRV_IF" | grep $VIP | sed 's/^/     /'

echo ""
echo "🔑 Thông ngay. Router tự ARP lại, node-b trả lời, xong."
echo "   => Chứng minh: entry sai trên ROUTER là nguyên nhân duy nhất."
echo "   ⚠️  Nhưng đây chỉ là ĐƯỜNG CHỮA CHÁY, không phải cách làm đúng:"
echo "      • phải có quyền SSH/enable vào router — đội ứng dụng thường không có;"
echo "      • có bao nhiêu thiết bị L3 trong subnet đó thì phải gõ bấy nhiêu lần;"
echo "      • lần failover sau lặp lại y nguyên."
echo "   Cách đúng vẫn là ./scripts/2-fix.sh — arping trên node-b, sửa cho tất cả cùng lúc."
echo "   Lệnh tương đương trên thiết bị thật:  clear ip arp $VIP   (Cisco IOS)"
