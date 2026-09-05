#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 3 — CA BỆNH: SCRIPT HA TỰ CHẾ CƯỚP VIP MÀ QUÊN GARP
#
# ⚠️ Vì sao phải GIẾT Keepalived trước mới dựng được ca bệnh?
#    Vì Keepalived KHÔNG BAO GIỜ quên phát GARP — không có tuỳ chọn nào tắt
#    được. Đặt cả nhóm garp_master_* về 0 thì số gói giảm từ 5 xuống 1, nhưng
#    KHÔNG về 0. Nói cách khác: ca bệnh này chỉ tồn tại khi bạn KHÔNG dùng
#    Keepalived mà tự viết bash/Ansible/systemd ExecStartPost để gán VIP.
#
# Đây chính là nguyên nhân số 1 ngoài production.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 [1/3] Giết Keepalived trên node-b (giả lập: cụm này dùng script tự chế)..."
docker exec $NODE_B ka-stop

echo "🚨 [2/3] Giết node-a — MASTER chết đột ngột..."
docker compose kill node-a >/dev/null 2>&1
sleep 3

echo "🚨 [3/3] 'Script tự chế' của node-b cướp VIP — ĐÚNG MỘT DÒNG, không GARP:"
echo "        docker exec $NODE_B ip addr replace $VIP/24 dev eth0"
docker exec $NODE_B ip addr replace $VIP/24 dev eth0
sleep 2

echo ""
echo "=========================================="
echo "🩺 BẮT MẠCH: mọi thứ 'đúng' hết, nhưng dịch vụ chết"
echo "=========================================="
echo "VIP $VIP hiện nằm trên: $(vip_owner)   ← ĐÚNG chỗ"
echo "MAC thật của node-b:    $(mac_of $NODE_B)"
echo ""
echo "HAProxy trên node-b có khoẻ không?"
docker exec $NODE_B curl -s --max-time 2 "http://127.0.0.1:8404/;csv" \
    | awk -F, 'NR>1 && $2!="" {printf "   %-8s %-8s %s\n", $1, $2, $18}'
echo "   ← Backend UP hết. Dịch vụ sống 100%."

echo ""
echo "=========================================="
echo "🔎 BA BẢNG ARP — ai đang nói dối?"
echo "=========================================="
in_bang_arp
echo ""
echo "   client-remote:"
docker exec $CLIENT_REMOTE ip neigh show | sed 's/^/      /'
echo "      ↑ KHÔNG có dòng nào cho $VIP. Máy này khác subnet nên nó chỉ biết"
echo "        gateway. Bạn có soi bảng ARP ở đây cả ngày cũng KHÔNG thấy gì sai."

echo ""
echo "=========================================="
echo "💀 HẬU QUẢ"
echo "=========================================="
for C in $CLIENT_LAN $CLIENT_REMOTE; do
    # `set -e` sẽ giết script khi curl trả về != 0 -> phải bắt mã lỗi tường minh.
    OUT=$(docker exec "$C" curl -s -o /dev/null --max-time 4 -w '%{http_code}' "http://$VIP/" 2>/dev/null) \
        && RC=0 || RC=$?
    printf "   %-24s http_code=%-4s curl_exit=%s %s\n" "$C" "${OUT:-0}" "$RC" \
           "$([ "$RC" = "28" ] && echo '← TIMEOUT, không có response nào')"
done

echo ""
echo "🔑 Ổ BỆNH nằm ở bảng ARP của ROUTER, không phải ở client."
echo "   Router vẫn forward frame tới MAC của node-a — một máy đã tắt thở."
echo "   Toàn bộ client ở MỌI subnet khác đều chết theo, mà không ai trong số"
echo "   họ có bất kỳ dấu hiệu bất thường nào trên máy mình."
echo ""
echo "👉 Chẩn đoán đầy đủ: ./scripts/test.sh"
echo "👉 Chữa đúng cách:   ./scripts/4-fix.sh"
echo "👉 Không chữa, đo tự khỏi: ./scripts/5-tu-khoi.sh"
