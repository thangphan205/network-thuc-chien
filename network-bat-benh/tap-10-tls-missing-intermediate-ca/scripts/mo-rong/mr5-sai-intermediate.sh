#!/usr/bin/env bash
# ==============================================================================
# MR5 — 2 CERT, NHUNG SAI NGUOI KY.  Chu ky: #cert=2, num=20, DEPTH=0.
#
# ⚠️ KICH BAN NAY TON TAI DE PHA MOT LUAT BAN VUA HOC O KB1/KB2/KB3.
#
#    Den gio ban dang dung phep DEM CERT lam chi bao:
#        1 cert  ->  server gui thieu
#        2 cert  ->  server da lam du phan viec
#    Luat thu hai SAI. Server o day gui du 2 cert — va van hong y het KB2.
#
#    Vi cert thu hai la intermediate cua MOT CA HOAN TOAN KHAC. No khong ky cho
#    leaf. No chi don gian nam do, chiem cho, va lam phep dem cert tra loi nham.
#
# Tinh huong ngoai doi (rat pho bien, khong he hiem):
#   • Server host nhieu site, moi site mua cert tu mot CA khac nhau. Copy nham
#     file .ca-bundle tu thu muc site ben canh.
#   • CA doi intermediate (vi du Let's Encrypt R3 -> R10/R11). Script gia han
#     cap leaf moi do R11 ky, nhung file bundle tren dia van la R3 cu.
#   • Dan nham doan PEM trong email cua CA — trong email thuong co CA HAI ban
#     intermediate cho hai dong san pham khac nhau.
#
# 🧠 QUY TAC DUNG, thay cho phep dem:
#        issuer cua tang N  PHAI TRUNG  subject cua tang N+1
#    Doc `s:` va `i:` theo TUNG CAP. Script in san bang doi chieu o duoi.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR5 — server gui 2 cert, nhung cert thu hai la cua CA khac..."
cai_root
dat_chuoi sai-int

buoc "CHU KY: DEM DU CERT MA VAN DUT"
RAW=$(_bat_tay)
in_chu_ky
echo ""
echo "  Doi chieu TUNG MAT XICH (thu doan phep dem cert khong lam duoc):"
kiem_mat_xich "$RAW"
echo ""
echo "👉 Doc chu ky:"
echo "   • #cert = 2, y het KB1 va KB3. Phep dem KHONG phat hien ra gi."
echo "   • num=20 DEPTH=0 — y het KB2. Cert hong van la leaf."
echo "   • Nhin bang doi chieu o tren: nguoi ky ma leaf CAN, va cert server GUI"
echo "     KEM, la hai phap nhan khac nhau. Do la cho dut."
echo "   • Chua: lay dung file bundle cua CA da ky leaf nay. Doi chieu bang"
echo "     'issuer cua leaf' chu khong phai bang 'da co file bundle chua'."
echo ""
echo "   🧠 Cap nhat lai luat da hoc:"
echo "        SAI :  2 cert  =>  server da lam dung"
echo "        DUNG:  issuer(tang N) == subject(tang N+1), voi MOI N"
echo "      Phep dem chi la goi y. Doi chieu cap moi la bang chung."
