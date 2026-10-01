#!/usr/bin/env bash
# ==============================================================================
# MR1 — CHUOI DAO NGUOC.  Chu ky: nginx TU CHOI KHOI DONG.
#
# File chuoi bi ghep nguoc: intermediate dung truoc, leaf dung sau.
#     cat intermediate.crt server.crt > chuoi.crt      <- SAI
#     cat server.crt intermediate.crt > chuoi.crt      <- DUNG
#
# Thu tu trong file CHINH LA thu tu tren day, va TLS quy dinh cert DAU TIEN phai
# la cert cua server. nginx lay cert dau tien roi doi chieu voi private key —
# khong khop, nen no chet ngay luc khoi dong.
#
# ⚠️ VI SAO KICH BAN NAY DANG GIA:
#    Day la ca benh DUY NHAT trong tap bi bat NGAY, truoc khi co client nao ket
#    noi. Doi lap han voi KB2/KB3 — hai ca do server khoi dong hoan toan binh
#    thuong, im lang phuc vu sai trong nhieu thang.
#    Bai hoc: mot cau hinh TLS khoi dong duoc KHONG chung minh dieu gi ca. Cai
#    chet ngay la cai de nhat; cai dang so la cai chay ngon lanh.
#
#    Va khong phai proxy nao cung nghiem nhu nginx. Mot so bo can bang tai chap
#    nhan chuoi sai thu tu roi day nguyen no ra Internet — luc do ban lai roi ve
#    dung chu ky cua KB2: client bao 20, con server thi "van chay binh thuong".
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR1 — ghep chuoi NGUOC (intermediate truoc, leaf sau)..."
cai_root
dat_chuoi dao-nguoc

buoc "CHU KY: SERVER KHONG KHOI DONG DUOC"
in_chu_ky
echo ""
echo "👉 Doc chu ky:"
echo "   • Loi nam trong LOG CUA NGINX, khong nam o phia client. Client chi thay"
echo "     'Connection refused' — mot trieu chung o TANG 4, dan ban di sai huong"
echo "     hoan toan neu khong ngo len xem log server."
echo "   • 'key values mismatch' = nginx lay cert dau file (intermediate) roi so"
echo "     voi private key cua leaf. Hai cai khong cung mot cap khoa."
echo "   • Chua: ghep lai dung thu tu — LEAF TRUOC, roi moi den intermediate."
echo ""
echo "   🧠 Quy tac ghep chuoi, tu duoi len tren:"
echo "        cat leaf.crt intermediate.crt > fullchain.crt"
echo "      Doc tu tren xuong trong file = di tu server ve phia root."
