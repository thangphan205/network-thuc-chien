#!/usr/bin/env bash
# ==============================================================================
# GOC NHIN PHIA SERVER — mo o terminal thu 3, chay suot buoi hoc.
#
#   ./scripts/xem-chuoi.sh [nhip_giay]
#
# Vi sao can mot khung nhin RIENG cho phia server?
#   Vi ca tap nay noi ve viec TRACH NHIEM BI CHIA DOI: server gui phan duoi cua
#   chuoi, client giu phan tren. Chi nhin mot phia thi khong bao gio tach duoc
#   "server gui thieu" voi "client thieu root" — hai ca in ra y het nhau.
#
# ⚠️ Cot "chuoi trong conf" va "chuoi TREN DAY" co the LECH NHAU. Do la truong
#    hop kinh dien: da sua file cau hinh nhung chua reload nginx. Khung nay bat
#    duoc no ngay, vi mot cot doc tu DIA con cot kia doc tu DAY.
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

NHIP=${1:-3}

echo "🖥️  GÓC NHÌN PHÍA SERVER — Ctrl+C để dừng"
echo ""

while true; do
    clear 2>/dev/null || true
    echo "=============================================================="
    echo " GÓC NHÌN PHÍA SERVER ($WEB)                 $(date -u '+%H:%M:%S') UTC"
    echo "=============================================================="
    echo ""
    echo " nginx                 : $(nginx_song)"
    echo " Chuỗi trong conf      : $(chuoi_dang_dat)      <- đọc từ ĐĨA"

    if [ "$(nginx_song)" != "ĐANG CHẠY" ]; then
        echo ""
        echo " ❌ nginx không khởi động được. Lý do:"
        nginx_ly_do_chet | sed 's/^/    /'
        echo ""
        echo " (làm mới mỗi ${NHIP}s — Ctrl+C để dừng)"
        sleep "$NHIP"
        continue
    fi

    RAW=$(_bat_tay)
    IFS='|' read -r NUM DEPTH MSG <<<"$(verify_chi_tiet "$RAW")"
    IFS='|' read -r CODE RC CMSG <<<"$(curl_thu)"

    echo " ------------------------------------------------------------"
    echo " CHUỖI THỰC SỰ GỬI RA DÂY: $(so_cert_gui "$RAW") cert"
    chuoi_gui_ra "$RAW"
    echo ""
    A=$(aia_url "$RAW")
    echo " AIA trong cert        : ${A:-(không có)}"
    echo " ------------------------------------------------------------"
    echo " PHÍA CLIENT:"
    echo "   Trust store         : $(co_root)"
    echo "   openssl verify      : num=$NUM  DEPTH=$DEPTH"
    echo "                         $MSG"
    echo "   curl                : http=$CODE exit=$RC ${CMSG:+— $CMSG}"
    echo ""
    echo " ------------------------------------------------------------"
    echo " Hạn của từng cert trên đĩa:"
    docker exec $CLIENT sh -c \
        'for f in /etc/ssl/lab/rootCA.crt /etc/ssl/lab/intermediateCA.crt /etc/ssl/lab/intHetHan.crt /etc/ssl/lab/server.crt; do
             [ -e "$f" ] || continue
             printf "   %-22s %s\n" "$(basename $f)" "$(openssl x509 -in $f -noout -enddate | sed s/notAfter=//)"
         done' 2>/dev/null || true
    echo ""
    echo " (làm mới mỗi ${NHIP}s — Ctrl+C để dừng)"
    sleep "$NHIP"
done
