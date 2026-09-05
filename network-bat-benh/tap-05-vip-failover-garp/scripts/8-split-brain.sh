#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 8 — SPLIT-BRAIN: THỪA GARP TỪ HAI NGUỒN
#
# Ca bệnh ở kịch bản 3 là "thiếu GARP". Ca này ngược lại và nguy hiểm hơn nhiều:
# cả HAI node cùng tin mình là MASTER, cùng giữ VIP, cùng bắn GARP.
# Bảng ARP của toàn LAN bị giằng qua giằng lại giữa hai MAC.
#
# Nguyên nhân ngoài đời: đứt đường VRRP heartbeat (VLAN sai, switch chặn
# multicast 224.0.0.18, firewall chặn protocol 112, link riêng cho heartbeat
# chết) — trong khi cả hai node vẫn sống và vẫn phục vụ được.
#
# Lab mô phỏng bằng cách chặn đúng gói VRRP giữa 2 node, giữ nguyên mọi thứ khác.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

khoi_phuc() {
    echo ""
    echo "🧹 Dọn dẹp: bỏ chặn VRRP, khởi động lại Keepalived cho hội tụ..."
    for N in $NODE_A $NODE_B; do
        docker exec "$N" iptables -D INPUT -p 112 -j DROP 2>/dev/null || true
        docker exec "$N" pkill -9 keepalived 2>/dev/null || true
        docker exec "$N" ip addr del $VIP/24 dev eth0 2>/dev/null || true
    done
    sleep 1
    for N in $NODE_A $NODE_B; do docker exec "$N" ka-start; done
    sleep 6
    echo "   VIP giờ nằm trên: $(vip_owner)"
    echo "👉 Chạy ./scripts/0-setup.sh để về trạng thái chuẩn."
}
trap khoi_phuc EXIT

A_MAC=$(mac_of $NODE_A); B_MAC=$(mac_of $NODE_B)
echo "📋 Trước khi gây lỗi:"
echo "   VIP nằm trên : $(vip_owner)"
echo "   MAC node-a   : $A_MAC"
echo "   MAC node-b   : $B_MAC"

echo ""
echo "💥 Chặn gói VRRP (IP protocol 112) ở CẢ HAI node — mô phỏng đứt heartbeat..."
docker exec $NODE_A iptables -I INPUT -p 112 -j DROP
docker exec $NODE_B iptables -I INPUT -p 112 -j DROP

echo "⏳ Chờ 8 giây cho node-b hết hạn chờ advertisement và tự lên MASTER..."
sleep 8

echo ""
echo "=========================================="
echo "📊 AI ĐANG GIỮ VIP?"
echo "=========================================="
A_HAS=$(docker exec $NODE_A ip -o addr show eth0 | grep -c "$VIP" || true)
B_HAS=$(docker exec $NODE_B ip -o addr show eth0 | grep -c "$VIP" || true)
echo "   node-a giữ VIP: $([ "$A_HAS" -gt 0 ] && echo 'CÓ' || echo 'không')"
echo "   node-b giữ VIP: $([ "$B_HAS" -gt 0 ] && echo 'CÓ' || echo 'không')"

if [ "$A_HAS" -gt 0 ] && [ "$B_HAS" -gt 0 ]; then
    echo ""
    echo "   ❌ SPLIT-BRAIN: hai máy cùng mang một địa chỉ IP trên cùng một LAN."
fi

echo ""
echo "=========================================="
echo "🔬 BẰNG CHỨNG: HỎI ARP THÌ AI TRẢ LỜI?"
echo "=========================================="
echo "   Xoá ARP của client rồi hỏi lại VIP — đếm xem có mấy máy đáp:"
docker exec $CLIENT_LAN ip neigh flush dev eth0 2>/dev/null || true
docker exec $CLIENT_LAN arping -c 4 -I eth0 "$VIP" 2>&1 | sed 's/^/   /' || true

echo ""
echo "   👉 SỐ CÂU TRẢ LỜI NHIỀU HƠN SỐ CÂU HỎI, đến từ HAI MAC khác nhau."
echo "      Đó là dấu vân tay kinh điển của duplicate IP / split-brain."
echo "      Trên hệ thống thật, đây là lệnh đầu tiên nên gõ khi nghi ngờ:"
echo "          arping -c 4 -I <iface> <VIP>"

echo ""
echo "=========================================="
echo "🔀 HAI BẢNG ARP ĐANG TRỎ VỀ ĐÂU? (theo dõi 6 lượt)"
echo "=========================================="
echo "   Với topology có router, split-brain nguy hiểm gấp đôi: bảng ARP của"
echo "   ROUTER cũng bị giằng co, mà nó phục vụ TOÀN BỘ client ở các subnet khác."
echo ""
echo "   Mỗi lượt xoá ARP rồi hỏi lại, để thấy AI ĐÁP TRƯỚC thì thắng lượt đó."
echo "   (Ngoài đời không ai xoá tay — cuộc đua này tự diễn ra mỗi lần entry hết"
echo "    hạn, hoặc mỗi lần garp_master_refresh của một trong hai node bắn ra.)"
echo ""
LB_IF=$(r_lb_if)
printf "   %-6s %-22s %-22s\n" "lượt" "router(.52)" "client-lan"
for i in 1 2 3 4 5 6; do
    docker exec $ROUTER     ip neigh flush dev "$LB_IF" 2>/dev/null || true
    docker exec $CLIENT_LAN ip neigh flush dev eth0     2>/dev/null || true
    docker exec $CLIENT_LAN    curl -s -o /dev/null --max-time 2 "http://$VIP/" 2>/dev/null || true
    docker exec $CLIENT_REMOTE curl -s -o /dev/null --max-time 2 "http://$VIP/" 2>/dev/null || true
    RM=$(router_vip_mac) ; CM=$(client_lan_vip_mac)
    printf "   %-6s %-22s %-22s\n" "$i" "$(mac_to_node "$RM")" "$(mac_to_node "$CM")"
    sleep 1
done
echo ""
echo ""
echo "   👉 ĐỌC BẢNG NÀY CHO ĐÚNG. Trong lab, gần như lượt nào cũng ra cùng một"
echo "      node — vì hai node nằm trên cùng một Linux bridge của Docker, độ trễ"
echo "      chênh nhau vài chục micro-giây, nên cuộc đua ARP có kẻ thắng ỔN ĐỊNH."
echo "      ĐỪNG kết luận 'split-brain thì bảng ARP luôn đứng yên'."
echo ""
echo "      Ngoài đời hai node nằm ở hai rack, hai switch, hai đường uplink khác"
echo "      nhau. Kẻ thắng đổi theo tải, theo đường đi, theo thời điểm — và mỗi"
echo "      thiết bị trong LAN có thể chốt một kẻ thắng KHÁC NHAU. Đó là lý do"
echo "      triệu chứng luôn được mô tả là 'lúc được lúc không, tuỳ máy'."
echo ""
echo "      Bằng chứng CHẮC CHẮN của split-brain không nằm ở bảng này, mà ở kết"
echo "      quả arping phía trên: SỐ ĐÁP > SỐ HỎI, và đến từ HAI MAC." 

echo ""
echo "=========================================="
echo "🔑 VÌ SAO CA NÀY TỆ HƠN 'QUÊN GARP'"
echo "=========================================="
echo "   - 'Quên GARP': hỏng dứt khoát, dễ thấy, tự khỏi sau vài chục giây."
echo "   - Split-brain: CHẬP CHỜN. Lúc được lúc không, tuỳ gói GARP nào tới sau."
echo "     Mỗi node lại giữ một nửa số kết nối -> lỗi ngẫu nhiên, log hai nơi."
echo "   - Với dịch vụ có ghi dữ liệu (DB, file), hai MASTER cùng ghi = MẤT DỮ LIỆU."
echo ""
echo "   Phòng tránh ngoài đời:"
echo "     - Đường heartbeat RIÊNG, tốt nhất là 2 đường độc lập."
echo "     - unicast_peer thay cho multicast (qua được switch chặn multicast)."
echo "     - Quorum / STONITH (Pacemaker) để bắt buộc chỉ 1 node được sống."
echo "     - Giám sát: cảnh báo ngay khi thấy 2 MAC cùng đáp cho 1 VIP."
