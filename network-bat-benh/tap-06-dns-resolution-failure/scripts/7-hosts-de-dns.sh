#!/usr/bin/env bash
# ==============================================================================
# KB7 — /etc/hosts DE LEN DNS.  Chu ky: dig DUNG nhung ung dung di SAI.
#
# Tinh huong ngoai doi: ai do them mot dong vao /etc/hosts hoi debug thang truoc
# roi quen xoa. Hoac cong cu trien khai ghi vao do. DNS server hoan toan vo can.
#
# Co che: ung dung KHONG hoi DNS truc tiep. No goi getaddrinfo(), va ham nay di
# theo thu tu trong /etc/nsswitch.conf — mac dinh la `hosts: files dns`, tuc la
# /etc/hosts TRUOC, DNS SAU. Con `dig` thi hoi THANG nameserver, KHONG BAO GIO
# doc /etc/hosts. Do la ly do hai cong cu noi hai chuyen khac nhau.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB7 — them mot dong de quen trong /etc/hosts cua client..."
xoa_log_dns
them_hosts "$IP_WEB_CU"
echo "   /etc/hosts hien co:"
docker exec $CLIENT grep lab.local /etc/hosts | sed 's/^/     /'

buoc "CHU KY: dig DUNG, UNG DUNG SAI"
in_chu_ky
echo ""
echo "  --- Thu tu tra cuu ten cua he thong (/etc/nsswitch.conf) ---"
docker exec $CLIENT grep '^hosts:' /etc/nsswitch.conf | sed 's/^/  /'

echo ""
echo "👉 Doc chu ky:"
echo "   • IP theo dig     = $IP_WEB  (dig hoi thang server — server tra DUNG)"
echo "   • IP theo NSS/app = $IP_WEB_CU  (ung dung doc /etc/hosts TRUOC)"
echo "   • Hai dong nay LECH NHAU. Do la toan bo chan doan cua KB7."
echo "   • curl 200 nhung vao SERVER CU — giong het KB6-A ve trieu chung ben ngoai,"
echo "     nhung khac han o cho: KB6 sua tren DNS SERVER, KB7 sua tren MAY CLIENT."
echo ""
echo "🔑 Bai hoc: neu ban chi dung dig de kiem tra, ban se ket luan 'DNS on' va"
echo "   dong ticket. Lenh dung de kiem tra la getent hosts <ten> — no di dung"
echo "   con duong ma ung dung di."
echo ""
echo "   Sap xep 3 cau hoi theo thu tu:"
echo "     1. getent hosts $TEN   -> ung dung THAT SU dung IP nao?"
echo "     2. dig $TEN            -> DNS server noi gi?"
echo "     3. Lech nhau?          -> thu pham nam TREN MAY CLIENT (hosts/nscd),"
echo "                               khong phai tren DNS server."
