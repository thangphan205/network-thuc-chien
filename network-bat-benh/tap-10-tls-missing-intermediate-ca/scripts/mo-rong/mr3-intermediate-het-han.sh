#!/usr/bin/env bash
# ==============================================================================
# MR3 — INTERMEDIATE HET HAN, LEAF CON HAN.  Chu ky: num=10, DEPTH=1.
#
# Chuoi day du 2 tang, thu tu dung, trust store day du. Cert cua server con han
# den tan nam sau. Va van hong.
#
# ⚠️ CAI BAY LON NHAT CUA KICH BAN NAY:
#    curl in ra "certificate has expired". Ky su doc dong do, di kiem tra cert
#    cua server, thay `notAfter` con xa lac, roi ket luan "curl bi loi gi ay".
#    Hoac te hon: cap lai leaf, deploy, va KHONG CHUA DUOC GI — vi leaf chua bao
#    gio la thu het han.
#
#    Con so depth=1 tra loi thang cau hoi "cai NAO het han". Khong co no thi ban
#    dang doan mo giua hai kha nang.
#
# Tinh huong ngoai doi: CA noi bo dung intermediate 5 nam roi quen; cross-sign
# cua mot CA cong cong het han (vu AddTrust 2020, Let's Encrypt DST Root 2021 —
# ca hai deu lam sap hang loat he thong trong khi cert cua server con han).
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR3 — intermediate het han tu 01/01/2024, leaf van con han..."
cai_root
dat_chuoi int-het-han

buoc "CHU KY: HET HAN — NHUNG KHONG PHAI CAI BAN NGHI"
in_chu_ky
echo ""
echo "  Han cua TUNG TANG trong chuoi:"
docker exec $CLIENT sh -c \
  "for f in /etc/ssl/lab/serverHH.crt /etc/ssl/lab/intHetHan.crt; do
       printf '    %-22s ' \"\$(basename \$f)\"
       openssl x509 -in \$f -noout -enddate
   done" 2>/dev/null || true
echo ""
echo "👉 Doc chu ky:"
echo "   • num=10 'certificate has expired' — giong het tap 09 KB2."
echo "   • Nhung DEPTH=1, khong phai 0. Cai het han la INTERMEDIATE."
echo "   • Leaf (tang 0) con han toi nam sau. Cap lai leaf = chua nham nguoi,"
echo "     va sau khi deploy xong loi van y nguyen."
echo "   • Chua: xin CA cap ban intermediate moi, ghep lai fullchain, reload."
echo ""
echo "   🧠 Doc thong bao het han thi luon hoi them MOT cau:"
echo "        'cai nao het han — tang 0 hay tang 1?'"
echo "      Cung mot dong chu, hai cong viec sua chua hoan toan khac nhau."
