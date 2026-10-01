#!/usr/bin/env bash
# ==============================================================================
# MR1 — NAT "tha" goi giua chung (tcp_loose=1) — khong phai thuoc chua
#
# Cung established timeout 5s nhu KB2, chi doi DUY NHAT mot co: tcp_loose=1.
# Voi TCP, goi khong khop entry nao ma KHONG phai SYN thi mac dinh (loose=0)
# bi coi la INVALID -> DROP (KB2). Bat loose=1, kernel THU "nhat" no vao lam
# mot entry MOI (mid-stream pickup) thay vi coi la xa la.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

buoc "MR1 — established timeout = 5s, tcp_loose=1 (mid-stream pickup)"
dat_tcp_timeout 5
dat_loose 1
dat_nginx dai
xac_nhan_sysctl net.netfilter.nf_conntrack_tcp_loose 1

echo "  Cung phep thu voi KB2 — chi khac loose=1:"
N=$(hai_get_qua_idle 7)
echo "  👉 So phan hoi HTTP 200 nhan duoc: ${N}/2"
echo ""
echo "👉 Doc chu ky:"
echo "   • loose=1 -> ket qua LAT NGUOC KB2: 2/2, ung dung khong thay gi bat"
echo "     thuong, dù NAT DA XOA entry cu that."
echo "   • ⚠️ Day KHONG PHAI thuoc chua. loose=1 chi 'tha' duoc goi neu CONG"
echo "     DICH cu VAN CON TRONG (khong ai chiem). Voi nhieu client dong thoi"
echo "     tren mot NAT that, xac suat cong bi chiem lai rat cao — luc do goi"
echo "     bi coi INVALID va roi ve dung chu ky KB2, chap chon khong doan truoc"
echo "     duoc. Kernel Linux moi mac dinh loose=0 chinh vi ly do nay."
echo "   • Thuoc chua that: TCP keepalive (xem KB3) — chu dong GIU session,"
echo "     khong dua vao may man cua loose mode."
