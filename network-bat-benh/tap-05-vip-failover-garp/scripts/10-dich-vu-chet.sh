#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 10 — DỊCH VỤ CHẾT NHƯNG MÁY VẪN SỐNG
#
# Không giết node-a. Chỉ giết HAProxy trên nó.
# Máy vẫn ping được, VRRP advertisement vẫn phát bình thường — nhưng dịch vụ đã
# chết. Nếu Keepalived chỉ theo dõi "máy còn sống không" thì VIP sẽ nằm lì trên
# một node không phục vụ được gì.
#
# Đây là lý do phải có `vrrp_script` + `track_script`: Keepalived chủ động kiểm
# tra DỊCH VỤ (curl vào HAProxy), hỏng thì tự hạ priority (weight -30) để node
# kia giành VIP.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "📋 Trước: VIP nằm trên $(vip_owner), HAProxy node-a đang chạy."
echo ""
echo "💥 Giết HAProxy trên node-a (KHÔNG đụng vào Keepalived, máy vẫn sống)..."
docker exec $NODE_A pkill -9 haproxy 2>/dev/null || true

echo ""
echo "⏳ Theo dõi Keepalived tự phát hiện và chuyển VIP:"
for i in $(seq 10); do
    sleep 2
    printf "   t+%-3ss  VIP=%-10s  HTTP=%s\n" \
        "$((i*2))" "$(vip_owner)" \
        "$(docker exec $CLIENT_REMOTE curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://$VIP/ 2>/dev/null)"
    [ "$(vip_owner)" = "node-b" ] && break
done

echo ""
echo "📋 Sau: VIP nằm trên $(vip_owner)"
docker exec $CLIENT_REMOTE curl -s --max-time 3 -i "http://$VIP/" \
    | grep -iE '^HTTP/|^x-lb-node|^x-web-server'
echo ""
echo "👉 node-a vẫn sống, vẫn ping được — nhưng Keepalived đã chủ động nhường VIP"
echo "   vì chính nó phát hiện dịch vụ trên mình đã chết."
echo "   Thời gian phát hiện = interval(2s) × fall(2) + thời gian VRRP chuyển trạng thái."
echo ""
echo "👉 Reset: ./scripts/0-setup.sh"
