#!/usr/bin/env bash
# ==============================================================================
# Dựng lab về trạng thái BÌNH THƯỜNG:
#   Router định tuyến 3 tầng, Keepalived chạy trên cả 2 node, VIP nằm trên
#   node-a (MASTER), HAProxy cân bằng tải QUA ROUTER xuống web-1/web-2,
#   router và client-lan đã học đúng MAC của node-a.
# Chạy lại script này bất cứ lúc nào để reset sạch lab.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🔧 [1/6] Khởi động toàn bộ lab (router + HAProxy/Keepalived + 2 backend)..."
docker compose up -d --build

echo "🔧 [2/6] Dọn sạch dấu vết của cảnh trước rồi khởi động lại HA..."
# Reset PHẢI dứt khoát: các cảnh trước có thể để lại
#   - rule iptables chặn VRRP (cảnh 8 split-brain)
#   - keepalived đang chạy bằng cấu hình nopreempt (cảnh 9) hoặc use_vmac (cảnh 12)
#   - HAProxy bị giết (cảnh 10)
#   - VIP còn dính lại trên node sai (cảnh 3 gán tay)
# Vì vậy không dùng `ka-start` kiểu "đang chạy thì thôi" mà khởi động lại hẳn.
for N in $NODE_A $NODE_B; do
    docker exec "$N" iptables -D INPUT -p 112 -j DROP 2>/dev/null || true
    docker exec "$N" rm -f /etc/keepalived/USE_NOPREEMPT /etc/keepalived/USE_VMAC 2>/dev/null || true
    docker exec "$N" pkill -9 keepalived 2>/dev/null || true
    docker exec "$N" ip addr del $VIP/24 dev eth0 2>/dev/null || true
    # use_vmac để lại interface macvlan `vrrp51` — không xoá thì lần sau xung đột.
    docker exec "$N" ip link del vrrp51 2>/dev/null || true
    docker exec "$N" sh -c 'pgrep haproxy >/dev/null || haproxy -f /etc/haproxy/haproxy.cfg -D' 2>/dev/null || true
done
# Cảnh 11 để lại rule chặn .52 -> .53 trên router.
docker exec $ROUTER iptables -D FORWARD -s $LB_NET -d $APP_NET -p tcp --dport 80 -j DROP   2>/dev/null || true
docker exec $ROUTER iptables -D FORWARD -s $LB_NET -d $APP_NET -p tcp --dport 80 -j REJECT 2>/dev/null || true
# Cảnh 5 phần 2 để lại ARP timeout kiểu Cisco trên router.
set_arp_linux

echo "🔧 [3/6] Cài route tĩnh giữa 3 tầng..."
# Docker chỉ cho mỗi container default route ra bridge gateway CỦA CHÍNH NÓ
# (172.28.5x.1), không phải router của lab. Muốn đi xuyên tầng phải chỉ đường tay.
docker exec $CLIENT_REMOTE ip route replace $LB_NET     via $R_CLIENT
for N in $NODE_A $NODE_B; do
    docker exec "$N"       ip route replace $CLIENT_NET via $R_LB
    docker exec "$N"       ip route replace $APP_NET    via $R_LB
done
for W in $WEB_1 $WEB_2; do
    docker exec "$W"       ip route replace $LB_NET     via $R_APP
done
# client-lan KHÔNG cần route: nó ở cùng subnet với VIP.

sleep 1
# node-a lên trước để nó chiếm MASTER ngay, đỡ phải chờ preempt
docker exec $NODE_A ka-start /etc/keepalived/keepalived.conf 2>/dev/null || true
sleep 2
docker exec $NODE_B ka-start /etc/keepalived/keepalived.conf 2>/dev/null || true

echo "🔧 [4/6] Chờ VRRP hội tụ và HAProxy nhận backend (qua router)..."
if ! wait_vip_up 45; then
    echo "❌ VIP $VIP chưa phục vụ được. Kiểm tra:"
    echo "   docker compose logs"
    echo "   docker exec $NODE_A curl -s 'http://127.0.0.1:8404/;csv' | cut -d, -f1,2,18"
    exit 1
fi

echo "🔧 [5/6] Chờ node-a (priority 110) giành lại quyền MASTER..."
if ! wait_vip_owner node-a 30; then
    echo "⚠️  VIP đang nằm trên $(vip_owner) chứ không phải node-a."
    echo "   Kiểm tra: docker exec $NODE_A pkill -USR1 keepalived && docker exec $NODE_A cat /tmp/keepalived.data"
fi

luu_mac

echo "🔧 [6/6] Xoá bảng ARP cũ rồi gọi VIP để router + client-lan học lại MAC..."
docker exec $CLIENT_LAN ip neigh flush dev eth0
for IF in "$(r_cli_if)" "$(r_lb_if)" "$(r_app_if)"; do
    docker exec $ROUTER ip neigh flush dev "$IF" 2>/dev/null || true
done
docker exec $CLIENT_LAN    curl -s --max-time 3 -o /dev/null "http://$VIP/" || true
docker exec $CLIENT_REMOTE curl -s --max-time 3 -i "http://$VIP/" \
    | grep -iE '^HTTP/|^X-LB-Node|^X-Web-Server|<h1>'

echo ""
echo "✅ Trạng thái bình thường đã sẵn sàng."
echo "   VIP $VIP đang nằm trên: $(vip_owner)"
echo "   Bảng ARP đang trỏ về đâu:"
in_bang_arp
echo "   client-remote: KHÔNG có entry ARP cho VIP — đúng như mong đợi,"
echo "                  vì nó khác subnet nên chỉ ARP hỏi gateway $R_CLIENT."
echo ""
echo "👉 Mở terminal thứ 2 — máy đo phía client:"
echo "   docker exec -it $CLIENT_REMOTE monitor.sh"
echo "👉 Mở terminal thứ 3 — soi bảng ARP của router (ổ bệnh thật):"
echo "   ./scripts/xem-arp-router.sh"
