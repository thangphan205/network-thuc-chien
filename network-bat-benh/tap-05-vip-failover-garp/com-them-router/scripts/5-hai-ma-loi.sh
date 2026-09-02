#!/usr/bin/env bash
# ENTRY SAI nguy hiểm hơn KHÔNG CÓ ENTRY — chứng minh bằng 2 mã lỗi curl khác nhau.
# Cả hai trường hợp dịch vụ đều KHÔNG chạy, nhưng thông điệp báo về khác hẳn.
# Chạy sau 1-fault.sh. Script tự dọn về trạng thái cũ khi xong.
set -e
cd "$(dirname "$0")/.."
source scripts/_lib.sh
SRV_IF=$(r_srv_if)
DEAD_MAC=$(docker compose exec router ip neigh show dev "$SRV_IF" | awk "/$VIP/ {print \$3; exit}")

echo "🔧 Dựng cảnh: gỡ VIP khỏi node-b để KHÔNG AI giữ VIP nữa."
echo "   (Giờ dịch vụ chết thật — ta chỉ so cách hệ thống BÁO LỖI.)"
docker compose exec node-b ip addr del $VIP/24 dev eth0 2>/dev/null || true

echo ""
echo "🔸 [1] Router KHÔNG có entry → ARP hỏi, không ai đáp → ARP THẤT BẠI trung thực:"
docker compose exec router ip neigh flush dev "$SRV_IF"
docker compose exec client curl -s -S --max-time 5 http://$VIP 2>&1 | sed 's/^/     /'
echo "     👉 curl: (7) — báo lỗi NGAY, khoảng 3 giây. Router trả ICMP Host Unreachable."

echo ""
echo "🔸 [2] Router ÔM ENTRY SAI → ARP 'thành công' vào hư vô → BLACKHOLE IM LẶNG:"
docker compose exec router ip neigh replace $VIP lladdr "$DEAD_MAC" dev "$SRV_IF" nud reachable
docker compose exec client curl -s -S --max-time 5 http://$VIP 2>&1 | sed 's/^/     /'
echo "     👉 curl: (28) — treo hết timeout. Không ai báo gì cả."

echo ""
echo "🔑 Cùng một sự thật 'dịch vụ không chạy', hai thông điệp trái ngược:"
echo "   • (7)  Could not connect  = ARP thất bại TRUNG THỰC → có lỗi để đọc, để log, để cảnh báo."
echo "   • (28) Timed out          = ARP 'thành công' vào MAC ma → im lặng, không log, mò hàng giờ."
echo "   Bảng ARP SAI nguy hiểm hơn bảng ARP TRỐNG."

echo ""
echo "🔧 Dọn dẹp: trả VIP về node-b."
docker compose exec node-b ip addr replace $VIP/24 dev eth0
docker compose exec router ip neigh flush dev "$SRV_IF" 2>/dev/null || true
