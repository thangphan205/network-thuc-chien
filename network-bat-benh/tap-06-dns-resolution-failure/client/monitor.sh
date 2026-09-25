#!/usr/bin/env bash
# ==============================================================================
# MAY DO PHIA CLIENT — chay TRONG container client, de mo suot buoi hoc.
#
#   docker exec -it lab06-client monitor.sh [ten_mien] [nhip_giay]
#
# Moi vong in 4 cot, va 4 cot nay tach duoc TOAN BO cac ca benh cua tap:
#
#   DIG   : IP ma dig nhan duoc. dig hoi THANG nameserver, KHONG qua /etc/hosts,
#           KHONG qua nscd. Day la "su that phia DNS server".
#   NSS   : IP ma UNG DUNG that su dung (getent -> /etc/hosts -> nscd -> DNS).
#           DIG != NSS  =>  thu pham nam TREN MAY NAY, khong phai o DNS server
#           (KB7 /etc/hosts, KB8 bo dem).
#   HTTP  : ma tra ve + IP that su ket noi toi, hoac ma loi cua curl.
#   TRANG : tieu de trang -> biet dang noi chuyen voi may NAO.
#           DIG == NSS, HTTP 200, ma TRANG sai  =>  DNS tra loi dung DINH DANG
#           nhung SAI DIA CHI (KB6).
#
# ⚠️ Moi vong chi goi dig MOT lan va curl MOT lan. Khi dang co benh, moi lenh
#    deu phai cho het timeout — goi lap lai se lam mot vong dai hon 10 giay va
#    man hinh dung im, vo dung luc dang quay demo.
# ==============================================================================
TEN=${1:-web.lab.local}
NHIP=${2:-1}
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

printf "%-9s | %-15s | %-15s | %-22s | %s\n" "TIME" "DIG" "NSS (app)" "HTTP" "TRANG"
printf -- "-------------------------------------------------------------------------------------------------\n"
while true; do
    TS=$(date +%H:%M:%S)

    D=$(dig +short +time=1 +tries=1 "$TEN" 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
    [ -z "$D" ] && D="(khong ra)"

    N=$(getent hosts "$TEN" 2>/dev/null | awk '{print $1}' | head -1)
    [ -z "$N" ] && N="(khong ra)"

    # MOT lan curl duy nhat: than trang ghi ra file tam, ma va IP lay qua -w.
    R=$(curl -s -o "$TMP" --connect-timeout 2 --max-time 3 \
             -w '%{http_code} %{remote_ip}' "http://$TEN/" 2>/dev/null)
    RC=$?
    case $RC in
        0)  HTTP="$R" ; H1=$(sed -n 's/.*<h1>\(.*\)<\/h1>.*/\1/p' "$TMP" | head -1) ;;
        6)  HTTP="curl(6) khong phan giai duoc" ; H1="-" ;;
        7)  HTTP="curl(7) connection refused"   ; H1="-" ;;
        28) HTTP="curl(28) timeout"             ; H1="-" ;;
        *)  HTTP="curl($RC)"                    ; H1="-" ;;
    esac
    [ -z "$H1" ] && H1="-"

    printf "%-9s | %-15s | %-15s | %-22s | %s\n" "$TS" "$D" "$N" "$HTTP" "$H1"
    sleep "$NHIP"
done
