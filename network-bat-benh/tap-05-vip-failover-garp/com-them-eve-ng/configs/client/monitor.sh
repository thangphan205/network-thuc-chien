#!/usr/bin/env bash
# ==============================================================================
# CLIENT CONTINUOUS PROBE & SLA DOWNTIME MONITOR
# Path: /root/monitor.sh
# Usage: ./monitor.sh 172.28.52.100
# ==============================================================================

TARGET_VIP=${1:-"172.28.52.100"}
INTERVAL=1

echo "🔍 Bắt đầu giám sát liên tục VIP: http://$TARGET_VIP (Chu kỳ: ${INTERVAL}s)"
echo "Nhấn Ctrl+C để dừng."
echo "--------------------------------------------------------------------------------"
printf "%-10s | %-12s | %-20s | %-10s | %-25s\n" "TIME" "STATUS" "BACKEND" "LATENCY" "ARP GATEWAY"
echo "--------------------------------------------------------------------------------"

while true; do
    TIMESTAMP=$(date +"%H:%M:%S")
    GW_MAC=$(ip neigh show 172.28.51.254 | awk '{print $5}')
    
    # Đo đạc curl: lấy HTTP Code, thời gian phản hồi, Header server
    RESP=$(curl -s -S -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
         --connect-timeout 2 --max-time 3 \
         -D - http://$TARGET_VIP/ 2>&1) || CURL_ERR=$?

    if [ "${CURL_ERR:-0}" -eq 0 ]; then
        HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | cut -d':' -f2)
        TIME_TOTAL=$(echo "$RESP" | grep "TIME_TOTAL:" | cut -d':' -f2)
        BACKEND=$(echo "$RESP" | grep -i "X-Backend-Server:" | awk '{print $2}' | tr -d '\r')
        [ -z "$BACKEND" ] && BACKEND="OK (HTTP $HTTP_CODE)"

        printf "\033[0;32m%-10s | %-12s | %-20s | %-9ss | GW MAC: %s\033[0m\n" \
               "$TIMESTAMP" "SUCCESS" "$BACKEND" "$TIME_TOTAL" "$GW_MAC"
    else
        # Bắt mã lỗi curl đặc trưng
        ERR_MSG="curl err ($CURL_ERR)"
        if echo "$RESP" | grep -q "(28)"; then
            ERR_MSG="BLACKHOLE TIMEOUT (28)"
        elif echo "$RESP" | grep -q "(7)"; then
            ERR_MSG="CONN REFUSED (7)"
        fi
        printf "\033[0;31m%-10s | %-12s | %-20s | %-10s | GW MAC: %s\033[0m\n" \
               "$TIMESTAMP" "FAILED" "$ERR_MSG" "---" "$GW_MAC"
    fi

    CURL_ERR=0
    sleep "$INTERVAL"
done
