#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 7 — GARP DỪNG LẠI Ở BIÊN TẦNG 3
#
# Câu hỏi ai cũng hỏi sau kịch bản 4: "vậy cứ bắn thật nhiều GARP là xong chứ gì?"
# Đúng một nửa. Bắt gói ĐỒNG THỜI ở hai chỗ sẽ thấy nửa còn lại:
#
#   - Chân .52 của router (cùng broadcast domain với VIP)  -> CÓ nhận GARP
#   - eth0 của client-remote (bên kia router)              -> KHÔNG một gói nào
#
# ARP là giao thức Tầng 2. Gói GARP là broadcast Ethernet tới ff:ff:ff:ff:ff:ff,
# và router KHÔNG BAO GIỜ forward broadcast Tầng 2 sang subnet khác — nếu có thì
# mọi mạng lớn đã sập vì broadcast storm từ lâu.
#
# Vì vậy GARP không "sửa" client remote. Nó sửa ROUTER. Và vì client remote gửi
# mọi thứ qua router nên nó được cứu GIÁN TIẾP. Hiểu đúng chỗ này thì mới biết
# phải đi soi bảng ARP ở đâu khi sự cố xảy ra.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

LB_IF=$(r_lb_if)
CLI_IF=$(r_cli_if)
OWNER=$(vip_owner)
case "$OWNER" in
    node-a) TARGET=$NODE_A ;;
    node-b) TARGET=$NODE_B ;;
    *) echo "❌ Không node nào giữ VIP. Chạy ./scripts/0-setup.sh trước."; exit 1 ;;
esac

echo "📡 Bật tcpdump ĐỒNG THỜI ở 3 điểm đo, lọc đúng Gratuitous ARP:"
echo "     bộ lọc: arp[14:4] = arp[24:4]   (Sender IP == Target IP)"
echo "   1) router chân $LB_IF  — cùng subnet với VIP"
echo "   2) router chân $CLI_IF — chân hướng về client LAN"
echo "   3) client-remote eth0  — bên kia biên L3"
echo ""

docker exec -d $ROUTER        sh -c "tcpdump -i $LB_IF  -n -e -l 'arp[14:4] = arp[24:4]' > /tmp/garp-lb.txt  2>/dev/null"
docker exec -d $ROUTER        sh -c "tcpdump -i $CLI_IF -n -e -l 'arp[14:4] = arp[24:4]' > /tmp/garp-cli.txt 2>/dev/null"
docker exec -d $CLIENT_REMOTE sh -c "tcpdump -i eth0    -n -e -l 'arp[14:4] = arp[24:4]' > /tmp/garp.txt     2>/dev/null"
sleep 3

echo "💥 Bắn 5 gói GARP từ $OWNER (giống hệt kịch bản 4)..."
docker exec $TARGET arping -U -c 5 -I eth0 "$VIP" >/dev/null 2>&1 || true
sleep 3

docker exec $ROUTER        pkill tcpdump 2>/dev/null || true
docker exec $CLIENT_REMOTE pkill tcpdump 2>/dev/null || true
sleep 1

# `grep -c` in ra "0" VÀ thoát với mã 1 khi không khớp gì -> phải nuốt mã lỗi
# bằng `|| true`, không được `|| echo 0` (sẽ in ra hai dòng "0").
dem() { docker exec "$1" sh -c "grep -c 'Request who-has' '$2' 2>/dev/null || true" | tr -d '\r' | head -1; }

N_LB=$(dem  $ROUTER        /tmp/garp-lb.txt)
N_CLI=$(dem $ROUTER        /tmp/garp-cli.txt)
N_REM=$(dem $CLIENT_REMOTE /tmp/garp.txt)

echo ""
echo "=========================================="
echo "📊 SỐ GÓI GARP BẮT ĐƯỢC"
echo "=========================================="
printf "   %-34s %s gói %s\n" "router chân $LB_IF (LB LAN):"    "$N_LB"  "$([ "$N_LB"  -gt 0 ] && echo '✅ có nhận')"
printf "   %-34s %s gói %s\n" "router chân $CLI_IF (client LAN):" "$N_CLI" "$([ "$N_CLI" -eq 0 ] && echo '← router KHÔNG chuyển tiếp sang')"
printf "   %-34s %s gói %s\n" "client-remote eth0:"              "$N_REM" "$([ "$N_REM" -eq 0 ] && echo '← KHÔNG hề biết có chuyện gì')"

echo ""
echo "   Gói mà chân $LB_IF của router thấy:"
docker exec $ROUTER sh -c "head -3 /tmp/garp-lb.txt" 2>/dev/null | sed 's/^/      /'
echo "      ↑ Chữ ký của GARP: 'who-has <VIP> tell <VIP>' — hỏi về chính mình,"
echo "        gửi tới ff:ff:ff:ff:ff:ff. Đây là lời khai báo, không phải câu hỏi."

echo ""
echo "=========================================="
echo "🔑 ĐỌC KẾT QUẢ"
echo "=========================================="
echo "   - GARP dừng lại ở biên Tầng 3. Router nhận nó rồi NUỐT, không chuyển tiếp."
echo "   - Nên câu 'bắn thêm GARP cho client cập nhật' là SAI về mặt kỹ thuật."
echo "     GARP cập nhật ROUTER. Client remote được cứu gián tiếp, nhờ đi qua router."
echo ""
echo "   Hệ quả thực tế khi đi soi sự cố:"
echo "     - Bắt gói ở máy client remote để tìm GARP = chắc chắn không thấy gì."
echo "       Phải bắt ở một máy CÙNG SUBNET với VIP."
echo "     - Mỗi thiết bị L3 có chân trong subnet của VIP đều cần được cập nhật:"
echo "       router chính, router dự phòng, firewall, load balancer ngoài, HSRP/VRRP"
echo "       peer... Thiếu một cái là còn một đường chết."
echo "     - Bắt gói TRÊN CHÍNH NODE vừa failover là vô nghĩa: ở đó lúc nào cũng"
echo "       thấy gói đi ra. Phải bắt ở MÁY THỨ BA."
echo ""
echo "👉 Reset: ./scripts/0-setup.sh"
