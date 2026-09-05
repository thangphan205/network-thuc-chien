#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 12 — CHỮA TẬN GỐC: use_vmac (RFC 5798)
#
# Mọi cách chữa từ kịch bản 4 tới 6 đều là chữa TRIỆU CHỨNG: VIP nhảy sang máy
# khác, MAC đổi, nên phải đi báo cho cả LAN biết MAC mới. Còn phải báo là còn
# có ngày quên báo.
#
# use_vmac lật ngược vấn đề: MAC KHÔNG BAO GIỜ ĐỔI.
# Keepalived tạo một interface macvlan mang địa chỉ MAC ảo theo chuẩn VRRP:
#       00:00:5e:00:01:<VRID>
# MAC này giống hệt nhau trên MỌI node trong nhóm. Node nào lên MASTER thì
# interface đó UP trên máy đó. Với router, VIP vẫn ứng đúng một MAC như cũ —
# không có gì để cập nhật, nên cũng không có gì để quên.
#
# Đây là cách các thiết bị mạng thật (HSRP/VRRP trên Cisco, Juniper) vẫn làm
# từ đầu. Keepalived để mặc định TẮT vì macvlan không chạy được ở mọi môi trường.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

LB_IF=$(r_lb_if)

don_vmac() {
    for N in $NODE_A $NODE_B; do
        docker exec "$N" rm -f /etc/keepalived/USE_VMAC 2>/dev/null || true
        docker exec "$N" pkill -9 keepalived 2>/dev/null || true
        docker exec "$N" ip link del vrrp51 2>/dev/null || true
    done
}
trap 'echo ""; echo "🧹 Dọn cấu hình vmac..."; don_vmac; echo "👉 Chạy ./scripts/0-setup.sh để về trạng thái chuẩn."' EXIT

# Đo: MAC router ôm trước và sau failover, kèm downtime của client-remote.
do_failover() {
    local NHAN="$1"
    echo "   MAC router ôm TRƯỚC failover: $(router_vip_mac)"
    docker exec -d $CLIENT_REMOTE sh -c "ping -i 0.2 -W 1 $VIP > /tmp/ping.log 2>&1"
    sleep 3
    echo "   💥 SIGKILL node-a..."
    docker compose kill node-a >/dev/null 2>&1
    sleep 12
    docker exec $CLIENT_REMOTE pkill ping 2>/dev/null || true
    local GAP
    GAP=$(docker exec $CLIENT_REMOTE grep -o 'icmp_seq=[0-9]*' /tmp/ping.log 2>/dev/null | cut -d= -f2 \
          | awk 'NR==1{p=$1;m=0;next}{d=$1-p-1; if(d>m)m=d; p=$1}END{printf "%.1f", m*0.2}')
    echo "   MAC router ôm SAU failover:   $(router_vip_mac)"
    echo "   VIP giờ nằm trên: $(vip_owner)   |   downtime client-remote ≈ ${GAP}s"
}

# ------------------------------------------------------------------------------
echo "=============================================================="
echo "PHẦN 1 — KEEPALIVED MẶC ĐỊNH: MAC ĐỔI khi failover"
echo "=============================================================="
don_vmac
hoi_phuc_ha
docker exec $ROUTER ip neigh flush dev "$LB_IF"
docker exec $CLIENT_REMOTE curl -s --max-time 3 -o /dev/null "http://$VIP/" || true
echo "   MAC thật: node-a=$(mac_of $NODE_A)  node-b=$(mac_of $NODE_B)"
do_failover "mac-dinh"
echo ""
echo "   👉 MAC ĐỔI. Router chỉ biết được nhờ node-b chịu khó bắn GARP."
echo "      Bỏ GARP đi là ra đúng kịch bản 3."

# ------------------------------------------------------------------------------
echo ""
echo "=============================================================="
echo "PHẦN 2 — use_vmac: MAC KHÔNG ĐỔI"
echo "=============================================================="
hoi_phuc_ha
echo "🔧 Bật use_vmac trên cả 2 node rồi khởi động lại Keepalived..."
for N in $NODE_A $NODE_B; do
    # Cờ file để cấu hình sống sót qua `docker compose start` ở cuối kịch bản.
    docker exec "$N" touch /etc/keepalived/USE_VMAC
    docker exec "$N" pkill -9 keepalived 2>/dev/null || true
    docker exec "$N" ip addr del $VIP/24 dev eth0 2>/dev/null || true
done
sleep 1
docker exec $NODE_A ka-start /etc/keepalived/keepalived-vmac.conf
sleep 3
docker exec $NODE_B ka-start /etc/keepalived/keepalived-vmac.conf
wait_vip_up 45 >/dev/null 2>&1 || true
wait_vip_owner node-a 30 >/dev/null 2>&1 || true

echo ""
echo "   Interface mới trên node-a:"
docker exec $NODE_A ip -o link show vrrp51 2>/dev/null \
    | awk '{print "      "$2" MAC "$(NF-2)}' || echo "      (chưa tạo được)"
docker exec $NODE_A ip -o -4 addr show vrrp51 2>/dev/null | awk '{print "      IP "$4}'
echo "      ↑ 00:00:5e:00:01:33 — 0x33 = 51 = virtual_router_id. Đúng chuẩn RFC 5798."

docker exec $ROUTER ip neigh flush dev "$LB_IF"
docker exec $CLIENT_REMOTE curl -s --max-time 3 -o /dev/null "http://$VIP/" || true
sleep 1
echo ""
do_failover "vmac"

echo ""
echo "=============================================================="
echo "🔑 ĐỌC KẾT QUẢ"
echo "=============================================================="
echo "   - Phần 1: MAC trong bảng ARP của router ĐỔI sau failover."
echo "   - Phần 2: MAC KHÔNG đổi. Router không phải cập nhật gì cả."
echo ""
echo "   Hệ quả: toàn bộ ca bệnh của tập này BIẾN MẤT. Không cần GARP, không lo"
echo "   switch nuốt gói, không lo STP chưa forward, không lo ARP timeout 4 tiếng"
echo "   của Cisco. Downtime rút về đúng thời gian hội tụ VRRP và không hơn."
echo ""
echo "   Vậy sao không bật mặc định? Giá phải trả:"
echo "     - macvlan không chạy được ở mọi nơi: một số hypervisor, cloud VPC và"
echo "       switch bật port-security sẽ chặn frame có MAC lạ."
echo "     - Cổng switch nhìn thấy 2 MAC trên 1 cổng -> đụng giới hạn port-security."
echo "     - Khó soi hơn: MAC 00:00:5e:00:01:xx không tra ra được máy nào đang giữ."
echo "     - VRID phải là DUY NHẤT trong cùng broadcast domain. Hai cụm HA cùng"
echo "       dùng VRID 51 trên một VLAN = hai cụm cùng một MAC ảo = hỏng cả hai."
echo ""
echo "   Khuyến nghị: hạ tầng bạn kiểm soát được tầng 2 (bare-metal, VLAN riêng)"
echo "   thì bật use_vmac. Chạy trên cloud/hypervisor lạ thì giữ mặc định và đảm"
echo "   bảo GARP được bắn đủ (kịch bản 4)."
