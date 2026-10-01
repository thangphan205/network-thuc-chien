#!/usr/bin/env bash
# ==============================================================================
# MR3 — ⭐⭐ Server TU DONG theo gio rieng cua no — cap doi voi KB2
#
# Khong dung gi den GATEWAY ca. NAT established timeout van dai (432000s).
# Chi doi DUY NHAT keepalive_timeout cua chinh nginx tren SERVER xuong 3s.
# Idle 7s vuot qua -- nhung lan nay chinh SERVER tu gui FIN dong ket noi,
# DUNG GIAO THUC, co bao truoc. Ung dung nhan duoc "connection closed" ro
# rang, khong phai im lang treo nhu KB2.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

buoc "MR3 — nginx keepalive_timeout=3s, NAT timeout van DAI (khong dung gi)"
dat_tcp_timeout 432000
dat_loose 0
dat_nginx ngan

echo "  Cung mot phep thu, idle 7s (vuot 3s cua NGINX, KHONG vuot NAT):"
T0=$(date +%s)
N=$(hai_get_qua_idle 7)
T1=$(date +%s)
echo "  👉 So phan hoi HTTP 200 nhan duoc: ${N}/2   (mat $((T1-T0))s)"
echo ""
echo "  Bang conntrack cua gateway — chu y CO TRANG THAI, khong phai 'bien mat':"
xem_conntrack_80 | sed 's/^/     /'
echo ""
echo "👉 Doc chu ky — SO VOI KB2 (chay ./scripts/2-nat-xoa-im-lang.sh de doi chieu):"
echo "   ┌─────────────────────┬──────────────────┬──────────────────────┐"
echo "   │                     │ KB2 (NAT xoa)     │ MR3 (server tu dong) │"
echo "   ├─────────────────────┼──────────────────┼──────────────────────┤"
echo "   │ Ai la thu pham      │ GATEWAY (giua)    │ chinh SERVER          │"
echo "   │ Goi tin luc dong    │ KHONG CO GI       │ CO FIN dung giao thuc │"
echo "   │ conntrack sau do    │ entry BIEN MAT    │ entry con, state=CLOSE│"
echo "   │ Client cho bao lau  │ het TIMEOUT RIENG │ dong NGAY LAP TUC     │"
echo "   │ (~23s vs ~10s do thuc te trong lab nay)                        │"
echo "   └─────────────────────┴──────────────────┴──────────────────────┘"
echo "   • CUNG mot cau chuyen 'idle 7s la dut' — HAI thu pham hoan toan"
echo "     khac nhau. Chua sai cho: dat lai NAT timeout khong giai quyet"
echo "     duoc gi o day, phai sua/tang keepalive_timeout cua nginx."
