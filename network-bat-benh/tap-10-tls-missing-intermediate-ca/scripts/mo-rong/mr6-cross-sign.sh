#!/usr/bin/env bash
# ==============================================================================
# MR6 — CROSS-SIGN: cung mot chuoi byte, hai may, hai ket qua nguoc nhau.
#
# Day la mo hinh da lam sap Internet dien rong HAI LAN:
#   • 30/05/2020 — AddTrust External CA Root het han
#   • 30/09/2021 — DST Root CA X3 cua Let's Encrypt het han
# Ca hai lan, cert cua cac server deu CON HAN, khong ai deploy gi, va hang loat
# he thong chet dong loat trong cung mot phut.
#
# CO CHE:
#
#     [rootCu]  DA HET HAN                 [rootMoi]  con han
#         \\ ky                                 |
#          \\                                   |
#        [crossMoi]  <-- CUNG subject, CUNG khoa cong khai voi rootMoi.
#            |            Chi khac: no do rootCu ky.
#            |
#        [intR3]  -->  [serverX]
#
# Server gui MOT chuoi duy nhat: serverX + intR3 + crossMoi.
#   - May co rootMoi trong store  -> dung lai NGAY o rootMoi, khong them nhin
#                                     crossMoi   ->  OK
#   - May chi co rootCu           -> phai di het duong den rootCu da het han
#                                     ->  HONG, num=10 o DEPTH RAT CAO
#
# ⚠️ VI SAO NO NGUY HIEM HON MOI CA BENH TRUOC:
#    Khong co ai lam gi sai ca. Server dung. Cert con han. Cau hinh nginx dung.
#    Thu duy nhat xay ra la MOT NGAY TROI QUA. Va vi no phu thuoc vao trust
#    store cua TUNG may, ban se thay 60% nguoi dung binh thuong, 40% chet —
#    ty le do khong khop voi bat ky server/pod/region nao, nen moi cong cu
#    giam sat ha tang deu chi vao "khong co van de gi".
#
# 🧠 Va day la ly do con so DEPTH van la cong cu dung: depth cao (2, 3...) noi
#    ngay rang cho dut nam GAN ROOT, tuc la o phia trust store cua may — khong
#    phai o cau hinh server.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR6 — server gui chuoi cross-sign (leaf + R3 + ban cross do root CU ky)..."
cai_root
dat_chuoi cross-sign

buoc "CHUOI SERVER GUI RA DAY (chi co MOT, giong nhau cho moi may)"
RAW=$(_bat_tay)
echo "  So cert: $(so_cert_gui "$RAW")"
chuoi_gui_ra "$RAW"

buoc "CUNG CHUOI DO, HAI MAY, HAI KET QUA"
echo "  Lay dung cert ma server gui ra day..."
_trong_client "echo | openssl s_client -connect $IP_WEB:443 -servername $TEN -showcerts 2>/dev/null | sed -n '/BEGIN CERT/,/END CERT/p' > /tmp/x.pem"
_trong_client "awk 'BEGIN{n=0} /BEGIN CERT/{n++} {print > (\"/tmp/x\" n \".pem\")}' /tmp/x.pem"
echo ""
echo "  [MAY MOI] trust store CO 'Lab10 Root MOI':"
_trong_client "openssl verify -CAfile /etc/ssl/lab/rootMoi.crt -untrusted /tmp/x2.pem -untrusted /tmp/x3.pem /tmp/x1.pem 2>&1 | sed 's/^/      /'"
echo ""
echo "  [MAY CU]  trust store CHI CO 'Lab10 Root CU (het han 2024)':"
_trong_client "openssl verify -CAfile /etc/ssl/lab/rootCu.crt -untrusted /tmp/x2.pem -untrusted /tmp/x3.pem /tmp/x1.pem 2>&1 | sed 's/^/      /'"
echo ""
echo "  [MAY CU] neu bo qua han cua root (co che cac client cu ve sau bo sung):"
_trong_client "openssl verify -CAfile /etc/ssl/lab/rootCu.crt -untrusted /tmp/x2.pem -untrusted /tmp/x3.pem -no_check_time /tmp/x1.pem 2>&1 | sed 's/^/      /'"
echo ""
echo "👉 Doc chu ky:"
echo "   • Server gui DUNG MOT chuoi. Khong co gi khac nhau giua hai may."
echo "   • May moi: OK. May cu: 'certificate has expired' o DEPTH cao."
echo "   • DEPTH cao = cho dut nam GAN ROOT = van de o TRUST STORE cua may,"
echo "     khong phai o cau hinh server. Doi cert server o day khong chua duoc gi."
echo "   • Chua: cap nhat CA bundle tren may cu (ca-certificates, certifi,"
echo "     cacerts cua JVM). Hoac phia server: bo ban cross-sign ra khoi chuoi"
echo "     neu da khong con may cu nao can no."
echo ""
echo "   🧠 Bai hoc lon nhat cua ca tap nam o day:"
echo "        MOT chuoi cert co the co NHIEU duong di hop le."
echo "        Client tu chon duong. Client khac nhau chon khac nhau."
echo "      Vi vay cau hoi 'chuoi nay dung hay sai?' la cau hoi SAI."
echo "      Cau dung la: 'duong di ma MAY NAY dung duoc la duong nao?'"
