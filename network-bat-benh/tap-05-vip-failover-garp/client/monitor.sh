#!/usr/bin/env bash
# ==============================================================================
# GIÁM SÁT LIÊN TỤC VIP — chạy TRONG container client
# Mỗi giây in: trạng thái HTTP, LB nào phục vụ, backend nào trả lời, latency,
# và MAC liên quan tới VIP.
#
# Script này chạy đúng ở CẢ HAI client, nhưng cột cuối mang ý nghĩa KHÁC NHAU:
#   - client-lan (cùng subnet VIP): in MAC mà chính nó ôm cho VIP.
#   - client-remote (khác subnet):  nó KHÔNG BAO GIỜ ARP hỏi VIP, chỉ hỏi
#     gateway. Nên cột này in MAC của gateway — và MAC đó LUÔN ĐÚNG kể cả khi
#     dịch vụ chết. Đó chính là lý do soi bảng ARP ở client remote là ngõ cụt.
# ==============================================================================
VIP=${1:-172.28.52.100}
INTERVAL=${2:-1}

# VIP có on-link không? Có "via" trong route nghĩa là phải đi qua router.
GW=$(ip route get "$VIP" 2>/dev/null | sed -n 's/.* via \([0-9.]*\).*/\1/p' | head -1)
if [ -n "$GW" ]; then
    COL="GW MAC ($GW - KHONG phai MAC cua VIP)"
    WATCH="$GW"
else
    COL="ARP MAC CUA VIP"
    WATCH="$VIP"
fi

printf "%-9s | %-10s | %-8s | %-8s | %-9s | %s\n" \
       "TIME" "STATUS" "LB" "BACKEND" "LATENCY" "$COL"
printf -- "--------------------------------------------------------------------------------------------\n"

while true; do
    TS=$(date +%H:%M:%S)
    MAC=$(ip neigh show "$WATCH" 2>/dev/null | awk '{print $5}')
    [ -z "$MAC" ] && MAC="(chua hoc)"

    OUT=$(curl -s -i --connect-timeout 2 --max-time 3 "http://$VIP/" \
              -w '\nRC:%{http_code} T:%{time_total}\n' 2>/dev/null)
    RC=$(echo "$OUT" | sed -n 's/.*RC:\([0-9]*\).*/\1/p' | tail -1)
    T=$(echo  "$OUT" | sed -n 's/.*T:\([0-9.]*\).*/\1/p'  | tail -1)
    LB=$(echo "$OUT" | grep -i '^X-LB-Node:'    | tr -d '\r' | awk '{print $2}')
    BE=$(echo "$OUT" | grep -i '^X-Web-Server:' | tr -d '\r' | awk '{print $2}')

    if [ "$RC" = "200" ]; then
        printf "\033[0;32m%-9s | %-10s | %-8s | %-8s | %-8ss | %s\033[0m\n" \
               "$TS" "SUCCESS" "$LB" "$BE" "$T" "$MAC"
    elif [ "$RC" = "503" ]; then
        # CÓ response HTTP -> gói tin đi tới nơi về tới chốn, lỗi KHÔNG ở Tầng 2.
        # HAProxy sống, nhưng nó không với tới backend. Xem cảnh 11.
        printf "\033[0;33m%-9s | %-10s | %-8s | %-8s | %-8ss | %s\033[0m\n" \
               "$TS" "503 NO-BE" "${LB:-?}" "-" "$T" "$MAC"
    else
        # KHÔNG có response nào -> frame rơi vào hư vô. Đây mới là blackhole L2.
        printf "\033[0;31m%-9s | %-10s | %-8s | %-8s | %-9s | %s\033[0m\n" \
               "$TS" "BLACKHOLE" "-" "-" "---" "$MAC"
    fi
    sleep "$INTERVAL"
done
