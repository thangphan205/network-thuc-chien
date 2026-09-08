#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 9 — CHỮA SPLIT-BRAIN: BỎ MULTICAST, ĐI THẲNG UNICAST
#
# Kịch bản 8 cho thấy split-brain trông như thế nào. Kịch bản này chữa nó bằng
# đúng một khối cấu hình — và giải thích vì sao đó là thay đổi phổ biến nhất mà
# kỹ sư thật phải làm trên keepalived.
#
# ------------------------------------------------------------------------------
# KHÁC BIỆT VỚI KỊCH BẢN 8 — ĐỌC KỸ CHỖ NÀY
#
#   Kịch bản 8 chặn TOÀN BỘ protocol 112:   iptables -p 112 -j DROP
#       -> mô phỏng ĐỨT DÂY heartbeat. Unicast cũng chết. Không cứu được bằng
#          cấu hình, phải đi sửa dây.
#
#   Kịch bản 9 chỉ chặn VRRP gửi tới địa chỉ MULTICAST 224.0.0.18:
#       iptables -p 112 -d 224.0.0.18 -j DROP
#       -> mô phỏng đúng thứ gặp ngoài đời: DÂY VẪN TỐT, hai node vẫn ping được
#          nhau, chỉ riêng gói multicast bị nuốt. Ca này CHỮA ĐƯỢC bằng cấu hình.
#
# Ai nuốt multicast ngoài đời?
#   - Switch bật IGMP snooping mà VLAN không có querier -> gói multicast bị chặn
#   - storm-control / broadcast-suppression đặt ngưỡng thấp
#   - Hypervisor và VPC trên cloud: gần như KHÔNG NƠI NÀO cho multicast đi qua
#   - Firewall giữa hai node ở hai vùng khác nhau
#
# 👉 Đây là lý do trên cloud và trên hạ tầng ảo hoá, unicast_peer không phải
#    "tuỳ chọn nâng cao" mà là CẤU HÌNH BẮT BUỘC.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

MCAST=224.0.0.18

khoi_phuc() {
    echo ""
    echo "🧹 Dọn dẹp: bỏ chặn multicast, gỡ cờ unicast, đưa cụm về mặc định..."
    for N in $NODE_A $NODE_B; do
        docker exec "$N" iptables -D INPUT -p 112 -d $MCAST -j DROP 2>/dev/null || true
        docker exec "$N" rm -f /etc/keepalived/USE_UNICAST 2>/dev/null || true
        docker exec "$N" pkill -9 keepalived 2>/dev/null || true
        docker exec "$N" ip addr del $VIP/24 dev eth0 2>/dev/null || true
    done
    sleep 1
    docker exec $NODE_A ka-start /etc/keepalived/keepalived.conf 2>/dev/null || true
    sleep 2
    docker exec $NODE_B ka-start /etc/keepalived/keepalived.conf 2>/dev/null || true
    cho_dem_nguoc 6 "chờ cụm hội tụ lại"
    echo "   VIP giờ nằm trên: $(vip_owner)"
    echo "👉 Chạy ./scripts/0-setup.sh để về trạng thái chuẩn."
}
trap khoi_phuc EXIT

# Đếm số MAC khác nhau cùng đáp cho VIP — bằng chứng split-brain.
dem_mac_dap() {
    docker exec $CLIENT_LAN arping -c 4 -I eth0 "$VIP" 2>/dev/null \
        | grep -oiE '\[([0-9a-f]{2}:){5}[0-9a-f]{2}\]' | tr -d '[]' \
        | tr 'A-F' 'a-f' | sort -u
}

bao_cao() {
    local NHAN="$1" A_HAS B_HAS MACS SO
    A_HAS=$(docker exec $NODE_A ip -o addr show eth0 | grep -c "$VIP" || true)
    B_HAS=$(docker exec $NODE_B ip -o addr show eth0 | grep -c "$VIP" || true)
    MACS=$(dem_mac_dap) ; SO=$(echo "$MACS" | grep -c . || true)

    echo "   $NHAN"
    echo "      node-a giữ VIP : $([ "$A_HAS" -gt 0 ] && echo 'CÓ' || echo 'không')"
    echo "      node-b giữ VIP : $([ "$B_HAS" -gt 0 ] && echo 'CÓ' || echo 'không')"
    echo "      Số MAC đáp ARP : $SO"
    echo "$MACS" | while read -r m; do
        [ -n "$m" ] && echo "         $m  ($(mac_to_node "$m"))"
    done
    if [ "$SO" -gt 1 ]; then
        echo "      ❌ SPLIT-BRAIN — hai máy cùng mang một IP."
    elif [ "$SO" -eq 1 ]; then
        echo "      ✅ Đúng một chủ sở hữu."
    else
        echo "      ⚠️  Không ai đáp."
    fi
}

# ==============================================================================
echo "################################################################"
echo "# PHẦN 1 — SWITCH NUỐT MULTICAST (dây vẫn tốt)"
echo "################################################################"
echo "📋 Trạng thái ban đầu: VIP nằm trên $(vip_owner)"
echo ""
echo "💥 Chặn RIÊNG gói VRRP gửi tới multicast $MCAST trên cả hai node:"
echo "     iptables -I INPUT -p 112 -d $MCAST -j DROP"
echo "   (KHÔNG chặn unicast — đây là điểm khác với kịch bản 8)"
docker exec $NODE_A iptables -I INPUT -p 112 -d $MCAST -j DROP
docker exec $NODE_B iptables -I INPUT -p 112 -d $MCAST -j DROP

echo ""
echo "🔍 Chứng minh DÂY VẪN TỐT — hai node vẫn ping được nhau:"
docker exec $NODE_A ping -c 2 -W 1 172.28.52.12 2>&1 | tail -2 | sed 's/^/      /'
echo "   👉 Mạng thông hoàn hảo. Chỉ riêng heartbeat VRRP là không tới nơi."

cho_dem_nguoc 9 "chờ node-b hết hạn chờ advertisement rồi tự lên MASTER"
echo ""
bao_cao "📊 SAU KHI MULTICAST BỊ NUỐT:"

echo ""
echo "   Vì sao? Keepalived mặc định phát advertisement tới $MCAST. Không node"
echo "   nào nghe được node kia nữa, mỗi node kết luận 'đối phương đã chết' và"
echo "   tự lên MASTER. Cả hai cùng giữ VIP, cùng bắn GARP, bảng ARP của router"
echo "   bị giằng qua giằng lại."

# ==============================================================================
echo ""
echo "################################################################"
echo "# PHẦN 2 — unicast_peer: GỬI THẲNG, KHÔNG QUA MULTICAST"
echo "################################################################"
echo "🔧 Nạp lại Keepalived bằng cấu hình unicast trên cả hai node."
echo "   Rule chặn multicast VẪN CÒN NGUYÊN — không gỡ gì cả."
echo ""
echo "   node-a:  unicast_src_ip 172.28.52.11   unicast_peer { 172.28.52.12 }"
echo "   node-b:  unicast_src_ip 172.28.52.12   unicast_peer { 172.28.52.11 }"

for N in $NODE_A $NODE_B; do
    docker exec "$N" touch /etc/keepalived/USE_UNICAST
    docker exec "$N" pkill -9 keepalived 2>/dev/null || true
    docker exec "$N" ip addr del $VIP/24 dev eth0 2>/dev/null || true
done
sleep 1
docker exec $NODE_A ka-start /etc/keepalived/keepalived-unicast.conf
sleep 2
docker exec $NODE_B ka-start /etc/keepalived/keepalived-unicast.conf
cho_dem_nguoc 10 "chờ hai node nghe thấy nhau qua unicast và bầu lại MASTER"

echo ""
bao_cao "📊 SAU KHI BẬT unicast_peer (multicast VẪN đang bị chặn):"

echo ""
echo "🔍 Bằng chứng gói đã đổi đích — bắt VRRP trên node-b trong 4 giây:"
docker exec $NODE_B timeout 4 tcpdump -nn -i eth0 -c 3 'proto 112' 2>/dev/null \
    | sed 's/^/      /' || true
echo "   👉 Địa chỉ đích giờ là 172.28.52.12 (IP thật của node-b),"
echo "      KHÔNG còn là $MCAST. Rule chặn multicast không đụng tới nó."

# ==============================================================================
echo ""
echo "=========================================="
echo "🔑 ĐÚC KẾT"
echo "=========================================="
echo "   Cùng một sự cố mạng, khác nhau ở chỗ CHỮA ĐƯỢC hay KHÔNG:"
echo ""
echo "     Đứt dây heartbeat (KB8)  -> unicast cũng chết. Phải sửa hạ tầng."
echo "     Switch nuốt multicast    -> unicast_peer cứu được bằng cấu hình."
echo ""
echo "   Cách phân biệt trong 10 giây, trên máy thật:"
echo "     ping <ip node kia>                       # dây còn tốt không?"
echo "     tcpdump -nn -i <iface> proto 112         # có thấy advertisement không?"
echo "        thấy gói đi RA mà không thấy gói VÀO  -> đúng ca này"
echo ""
echo "   ⚠️  BA CÁI BẪY CỦA unicast_peer:"
echo "     1. Phải khai unicast_peer trên CẢ HAI node, mỗi node trỏ về node kia."
echo "        Khai một bên = một chiều nghe được, một chiều điếc -> vẫn split-brain."
echo "     2. Thiếu unicast_src_ip thì keepalived chọn IP nguồn theo route mặc"
echo "        định. Máy nhiều chân (bonding, VLAN, mạng quản trị riêng) rất dễ"
echo "        chọn nhầm IP khác subnet -> peer bỏ qua advertisement."
echo "     3. Cụm 3 node trở lên phải liệt kê ĐỦ mọi peer trong khối unicast_peer."
echo "        Multicast tự lo việc này, unicast thì không — thiếu ai là điếc với"
echo "        người đó. Đây là lý do cụm lớn vẫn thích multicast khi mạng cho phép."
echo ""
echo "   📌 Trên cloud (AWS/Azure/GCP) và trên hypervisor lạ: multicast gần như"
echo "      KHÔNG BAO GIỜ đi được. unicast_peer là bắt buộc, không phải tuỳ chọn."
echo "      (Nhưng nhớ: trên cloud thì GARP cũng chết — xem lại cảnh báo ở KB4.)"
echo ""
echo "   🔬 Kiểm chứng bằng công cụ giám sát:  ./scripts/kiem-tra-vip.sh"
