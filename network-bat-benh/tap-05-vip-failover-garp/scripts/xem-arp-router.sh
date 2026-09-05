#!/usr/bin/env bash
# ==============================================================================
# SOI BẢNG ARP CỦA ROUTER — mở ở terminal thứ 3 trong suốt buổi thực hành.
#
# Đây là Ổ BỆNH THẬT của tập này. Khi client và server khác subnet, client
# không bao giờ ARP hỏi VIP; kẻ ôm MAC chết sau failover là ROUTER.
# Trên thiết bị thật, dòng lệnh tương đương là:
#     Cisco IOS : show ip arp | include 172.28.52.100
#     Juniper   : show arp | match 172.28.52.100
# ==============================================================================
cd "$(dirname "$0")/.."
source scripts/lib.sh

IF=$(r_lb_if)
echo "Router $ROUTER — chân LB LAN = $IF   (Ctrl-C để thoát)"
printf "%-9s | %-20s | %-12s | %s\n" "TIME" "MAC ROUTER DANG OM" "TRANG THAI" "THUC TE VIP DANG O"
printf -- "-------------------------------------------------------------------------\n"

while true; do
    LINE=$(docker exec $ROUTER ip neigh show "$VIP" dev "$IF" 2>/dev/null)
    MAC=$(echo "$LINE"  | awk '{print $3}')
    NUD=$(echo "$LINE"  | awk '{print $NF}')
    OWNER=$(vip_owner)
    THEO_MAC=$(mac_to_node "$MAC")

    if [ -z "$MAC" ]; then
        printf "\033[0;33m%-9s | %-20s | %-12s | %s\033[0m\n" \
               "$(date +%H:%M:%S)" "(trong)" "-" "$OWNER"
    elif [ "$THEO_MAC" = "$OWNER" ]; then
        printf "\033[0;32m%-9s | %-20s | %-12s | %s\033[0m\n" \
               "$(date +%H:%M:%S)" "$MAC ($THEO_MAC)" "$NUD" "$OWNER  ✅"
    else
        printf "\033[0;31m%-9s | %-20s | %-12s | %s\033[0m\n" \
               "$(date +%H:%M:%S)" "$MAC ($THEO_MAC)" "$NUD" "$OWNER  ❌ LECH"
    fi
    sleep 1
done
