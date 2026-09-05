#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 11 — CÙNG LỜI THAN, KHÁC TẦNG BỆNH
#
# Người dùng báo y hệt kịch bản 3: "cụm HA vừa failover xong, dịch vụ không vào
# được". Nhưng lần này ổ bệnh KHÔNG ở bảng ARP.
#
# Backend nằm ở tầng app riêng (172.28.53.0/24) nên mọi health check của HAProxy
# đều phải đi QUA ROUTER. Một rule firewall chặn .52 -> .53 là đủ để HAProxy mất
# sạch backend — trong khi VIP vẫn đúng chỗ, ARP vẫn sạch, keepalived vẫn khoẻ.
#
# Phân biệt hai ca này CHỈ bằng một dấu hiệu:
#     Kịch bản 3  : KHÔNG có response nào  -> curl (28) timeout  -> lỗi Tầng 2
#     Kịch bản 11 : CÓ response HTTP 503   -> gói đi tới nơi     -> lỗi Tầng 3/7
#
# "Có response hay không" là câu hỏi đầu tiên phải trả lời trong mọi sự cố.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

go_rule() {
    docker exec $ROUTER iptables -D FORWARD -s $LB_NET -d $APP_NET -p tcp --dport 80 -j DROP   2>/dev/null || true
    docker exec $ROUTER iptables -D FORWARD -s $LB_NET -d $APP_NET -p tcp --dport 80 -j REJECT 2>/dev/null || true
}
trap 'echo ""; echo "🧹 Gỡ rule chặn trên router..."; go_rule' EXIT
go_rule

be_status() {
    docker exec "$1" curl -s --max-time 2 "http://127.0.0.1:8404/;csv" 2>/dev/null \
        | awk -F, 'NR>1 && $2 ~ /^web-/ {printf "%s=%s ", $2, $18}'
}

thu_chan() {
    local ACTION="$1" MOTA="$2"
    echo ""
    echo "=============================================================="
    echo "PHẦN: router chặn .52 -> .53 bằng $ACTION  ($MOTA)"
    echo "=============================================================="
    go_rule
    # Chờ HAProxy nhận lại backend trước khi đo lần sau.
    for _ in $(seq 15); do
        [ -z "$(be_status $NODE_A | grep -o DOWN)" ] && break
        sleep 1
    done
    echo "   Trước khi chặn: $(be_status $NODE_A)"

    docker exec $ROUTER iptables -I FORWARD -s $LB_NET -d $APP_NET -p tcp --dport 80 -j "$ACTION"
    local START; START=$(date +%s)
    local T_DOWN=""
    for _ in $(seq 20); do
        if [ -z "$(be_status $NODE_A | grep -o UP)" ]; then
            T_DOWN=$(( $(date +%s) - START )); break
        fi
        sleep 1
    done
    if [ -n "$T_DOWN" ]; then
        echo "   ⏱  HAProxy đánh dấu cả 2 backend DOWN sau ~${T_DOWN} giây"
    else
        echo "   ⚠️  Sau 20 giây backend vẫn UP — kiểm tra lại rule."
    fi
    echo "   Sau khi chặn:   $(be_status $NODE_A)"
    echo "   Client nhận:    $(docker exec $CLIENT_REMOTE curl -s -o /dev/null -w 'HTTP %{http_code} trong %{time_total}s' --max-time 5 "http://$VIP/" 2>/dev/null)"
}

echo "📋 Trạng thái ban đầu — mọi thứ khoẻ:"
echo "   VIP nằm trên: $(vip_owner)"
in_bang_arp

thu_chan DROP   "gói bị nuốt im lặng — giống tập 01"
thu_chan REJECT "gói bị từ chối có báo lại — giống tập 02"

go_rule
sleep 3

echo ""
echo "=============================================================="
echo "🔎 CHẨN ĐOÁN: vì sao đây KHÔNG phải ca bệnh ARP"
echo "=============================================================="
echo "   VIP $VIP vẫn nằm trên: $(vip_owner)   ← không hề chuyển"
in_bang_arp
echo "   ↑ Hai bảng ARP SẠCH TINH. Bạn có bắn bao nhiêu GARP cũng vô ích."
echo ""
echo "   Bảng phân biệt nhanh ba ca 'dịch vụ chết' trông giống hệt nhau:"
cat <<'TBL'

   Dấu hiệu              KB3 (ARP cũ)     KB11 (mất backend)  KB10 (HAProxy chết)
   --------------------- ---------------- ------------------- -------------------
   curl trả về           (28) timeout     HTTP 503            200 (sau ~7s)
   Có response HTTP?     KHÔNG            CÓ                  CÓ
   VIP có chuyển không?  đã chuyển rồi    KHÔNG               CÓ, tự chuyển
   Bảng ARP router       SAI (MAC chết)   ĐÚNG                ĐÚNG
   HAProxy stats         backend UP hết   backend DOWN hết    node kia phục vụ
   Sửa ở đâu             node giữ VIP     router / firewall   không cần sửa
TBL
echo ""
echo "   👉 Dòng 'HAProxy stats' là chỗ lật ngược trực giác:"
echo "      - KB3  : monitoring báo XANH HẾT mà dịch vụ chết. Monitoring bị mù,"
echo "               vì HAProxy chỉ nhìn XUỐNG backend, không biết gì về bảng ARP"
echo "               ở phía TRÊN nó."
echo "      - KB11 : monitoring báo ĐỎ đúng chỗ. Đây là ca dễ, nếu bạn chịu mở"
echo "               trang stats ra xem thay vì đoán."
echo ""
echo "   Ngoài đời KB11 xảy ra khi nào? Đổi rule firewall giữa DMZ và vùng app,"
echo "   security group / NACL siết lại, ACL trên core switch, hoặc microsegmentation"
echo "   mới bật. Thường không liên quan gì tới cụm HA — nhưng vì sự cố nổ ra ngay"
echo "   sau một lần failover nên ai cũng đổ tội cho HA trước."
echo ""
echo "👉 Reset: ./scripts/0-setup.sh"
