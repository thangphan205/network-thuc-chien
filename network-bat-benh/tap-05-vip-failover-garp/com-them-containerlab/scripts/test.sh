#!/usr/bin/env bash
# ==============================================================================
# CHẨN ĐOÁN TRẠNG THÁI LAB TRÊN CONTAINERLAB
# ==============================================================================
cd "$(dirname "$0")/.."
source scripts/lib-common.sh

ROUTER_MGMT_IOL="192.168.55.254"
ROUTER_USER="admin"
ROUTER_PASS="admin"

CLIENT_CTR=$(clab_ctr client)
S1_CTR=$(clab_ctr node-a)
S2_CTR=$(clab_ctr node-b)
ROUTER_CTR=$(clab_ctr router)

if [ -z "$CLIENT_CTR" ]; then
    echo "❌ Không tìm thấy container client. Hãy chạy ./scripts/deploy.sh trước."
    exit 1
fi

# Lấy MAC của một node (chuỗi aa:bb:cc:dd:ee:ff)
node_mac() { docker exec "$1" cat /sys/class/net/eth1/address 2>/dev/null; }

# Đổi MAC kiểu Linux (aa:bb:cc:dd:ee:ff) sang kiểu Cisco (aabb.ccdd.eeff)
to_cisco_mac() { echo "$1" | tr -d ':' | sed -E 's/(.{4})(.{4})(.{4})/\1.\2.\3/'; }

# Đọc bảng ARP trên router.
# Phân biệt router bằng LABEL clab-node-kind, KHÔNG dò bằng sự tồn tại của
# /proc/net/arp: container cisco_iol cũng là container Linux nên vẫn có
# /proc/net/arp (rỗng, vì stack IP nằm trong tiến trình iol.bin) -> dò kiểu đó
# sẽ luôn ra bảng ARP rỗng.
node_kind() { docker inspect -f '{{ index .Config.Labels "clab-node-kind" }}' "$1" 2>/dev/null; }

router_arp() {
    if [ "$(node_kind "$ROUTER_CTR")" = "linux" ]; then
        docker exec "$ROUTER_CTR" ip neigh show dev eth2
    elif command -v sshpass >/dev/null 2>&1; then
        # containerlab exec chỉ chạy được docker exec nên không vào được CLI của
        # IOL. Phải SSH vào management IP. IOL 17.x dùng thuật toán key cũ nên
        # cần bật lại diffie-hellman-group14-sha1 / ssh-rsa.
        sshpass -p "$ROUTER_PASS" ssh -q \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o KexAlgorithms=+diffie-hellman-group14-sha1 \
            -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAuthentication=no \
            "$ROUTER_USER@$ROUTER_MGMT_IOL" "show ip arp" 2>/dev/null \
            | tr -d '\r' | grep -E '^Internet'
    else
        echo "(Cần cài sshpass để đọc CLI Cisco: sudo apt-get install -y sshpass)"
        echo "(Hoặc thủ công: ssh $ROUTER_USER@$ROUTER_MGMT_IOL  -> show ip arp)"
    fi
}

S1_MAC=$(node_mac "$S1_CTR")
S2_MAC=$(node_mac "$S2_CTR")

echo "================================================================================"
echo "🩺 [BƯỚC 1] MAC THỰC TẾ TRÊN CÁC NODE:"
echo "================================================================================"
echo "Server 1 (MASTER): ${S1_MAC:-(Server 1 đang TẮT)}   [Cisco: $(to_cisco_mac "$S1_MAC")]"
echo "Server 2 (BACKUP): ${S2_MAC:-(Server 2 đang TẮT)}   [Cisco: $(to_cisco_mac "$S2_MAC")]"

echo ""
echo -n "VIP $VIP hiện nằm trên: "
if docker exec "$S1_CTR" ip addr show eth1 2>/dev/null | grep -q "$VIP"; then
    VIP_OWNER="Server 1"; VIP_MAC="$S1_MAC"
elif docker exec "$S2_CTR" ip addr show eth1 2>/dev/null | grep -q "$VIP"; then
    VIP_OWNER="Server 2"; VIP_MAC="$S2_MAC"
else
    VIP_OWNER="(Không node nào giữ VIP)"; VIP_MAC=""
fi
echo "$VIP_OWNER"

echo ""
echo "================================================================================"
echo "🩺 [BƯỚC 2] BẢNG ARP TRÊN CLIENT (ip neigh):"
echo "================================================================================"
# Mồi 1 gói tới gateway để bảng ARP có dữ liệu (lab vừa deploy xong thì bảng rỗng).
docker exec "$CLIENT_CTR" ping -c 1 -W 1 172.28.51.254 >/dev/null 2>&1 || true
docker exec "$CLIENT_CTR" ip neigh show dev eth1
echo "👉 Client chỉ thấy Gateway 172.28.51.254, hoàn toàn không biết VIP $VIP."

echo ""
echo "================================================================================"
echo "🩺 [BƯỚC 3] BẢNG ARP TRÊN ROUTER — AI ĐANG GIỮ $VIP?"
echo "================================================================================"
# Mồi 1 gói từ client về phía VIP để router buộc phải tra ARP (lab vừa deploy
# xong thì bảng ARP của router còn rỗng). Ở trạng thái đang lỗi, gói này rơi vào
# MAC chết nên entry sai vẫn giữ nguyên - đúng thứ ta cần soi.
docker exec "$CLIENT_CTR" ping -c 1 -W 1 "$VIP" >/dev/null 2>&1 || true
ARP_OUT=$(router_arp)
echo "$ARP_OUT"
ARP_LINE=$(echo "$ARP_OUT" | grep -F "$VIP" || true)
if [ -z "$ARP_LINE" ]; then
    echo "👉 Router chưa có entry ARP cho VIP (sẽ học khi có traffic đầu tiên)."
else
    if [ -n "$VIP_MAC" ] && echo "$ARP_LINE" | grep -qiE "$VIP_MAC|$(to_cisco_mac "$VIP_MAC")"; then
        echo "✅ Router đang trỏ ĐÚNG MAC của $VIP_OWNER."
    else
        echo "❌ Router đang ôm MAC CŨ — không khớp MAC của $VIP_OWNER đang giữ VIP!"
        echo "   Đây chính là ca bệnh: router forward frame vào MAC của node đã chết."
        echo "   Cisco giữ entry sai này tới 14400s (4 tiếng) nếu không có GARP."
    fi
fi

echo ""
echo "================================================================================"
echo "🩺 [BƯỚC 4] CLIENT GỌI DỊCH VỤ QUA VIP (curl):"
echo "================================================================================"
docker exec "$CLIENT_CTR" curl -s -S -i --connect-timeout 2 --max-time 3 "http://$VIP/" \
    | grep -iE "^HTTP/|^X-Backend-Server|<h1>" \
    || echo "❌ LỖI: Không gọi được dịch vụ qua VIP $VIP! (blackhole)"

echo ""
echo "================================================================================"
echo "🩺 [BƯỚC 5] CHIỀU NGƯỢC LẠI: NODE-B GỌI CLIENT (Kiểm tra bất đối xứng):"
echo "================================================================================"
docker exec "$S2_CTR" ping -c 2 -W 1 "$CLIENT_IP" 2>&1 | tail -3
echo "👉 Khi đang lỗi: chiều Server -> Client vẫn thông trong khi chiều Client -> VIP đứt."
echo "   Đó chính là dấu vân tay 'đứt một chiều' của bệnh ARP cache sai."
