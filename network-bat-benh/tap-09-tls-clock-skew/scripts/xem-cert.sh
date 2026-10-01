#!/usr/bin/env bash
# ==============================================================================
# GOC NHIN PHIA SERVER — mo o terminal thu 3, chay suot buoi hoc.
#
#   ./scripts/xem-cert.sh [nhip_giay]
#
# Vi sao can mot khung nhin RIENG cho phia server?
#   Vi ca tap nay noi ve viec HAI BEN nhin cung mot cert ma ra hai ket luan khac
#   nhau. Chi nhin phia client thi khong bao gio tach duoc "cert sai" voi "dong
#   ho toi sai". Khung nay in dong ho server + cert server DANG THUC SU serve.
#
# ⚠️ Cot "cert tren dia" va cot "cert tren day" co the LECH NHAU. Do la truong
#    hop kinh dien: da thay file cert nhung chua reload nginx.
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
    echo " GÓC NHÌN PHÍA SERVER ($WEB)                 $(date '+%H:%M:%S') GMT+7"
    echo "=============================================================="
    echo ""
    echo " Đồng hồ SERVER : $(gio_server) GMT+7"
    echo " Đồng hồ CLIENT : $(gio_client) GMT+7"
    echo " LỆCH           : $(lech_doc_duoc "$(lech_giay)")"
    echo ""
    echo " Cert đặt trong nginx.conf : $(cert_dang_dat).crt"
    echo " ------------------------------------------------------------"
    echo " CERT THỰC SỰ SERVE (đọc từ dây):"
    cert_tren_day | sed 's/^/   /'
    echo ""
    echo " openssl verify : $(verify_openssl)"
    IFS='|' read -r CODE RC MSG <<<"$(curl_thu)"
    echo " curl           : http=$CODE exit=$RC ${MSG:+— $MSG}"
    echo ""
    echo " ------------------------------------------------------------"
    echo " Cert có sẵn trong nginx/ssl/ (trên đĩa):"
    for f in nginx/ssl/*.crt; do
        [ -e "$f" ] || continue
        printf '   %-16s %s\n' "$(basename "$f")" \
            "$(openssl x509 -in "$f" -noout -dates 2>/dev/null | tr '\n' ' ')"
    done
    echo ""
    echo " (làm mới mỗi ${NHIP}s — Ctrl+C để dừng)"
    sleep "$NHIP"
done
