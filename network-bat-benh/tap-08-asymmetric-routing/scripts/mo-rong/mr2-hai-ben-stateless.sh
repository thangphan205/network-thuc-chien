#!/usr/bin/env bash
# MR2 — Bat doi xung KHONG phai loi: khong co thiet bi stateful thi chay binh thuong.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh
buoc "MR2 — duong ve bat doi xung, CA HAI router deu PERMISSIVE (khong theo doi trang thai)"
server_ve b; luat_permissive $FWA; luat_permissive $FWB
xoa_conntrack $FWA; xoa_conntrack $FWB
echo "  server ve LAN client qua : $(server_dang_ve)  (fw-b — van bat doi xung!)"
echo "  ping -> $(ping_thu)"
echo "  curl -> HTTP $(curl_thu)"
echo ""
echo "👉 Doc chu ky:"
echo "   • Duong ve VAN lech (fw-b) ma curl van 200."
echo "   • Asymmetric routing tu no KHONG lam hong gi. Loi chi xuat hien khi co it nhat"
echo "     MOT thiet bi stateful nam tren MOT trong hai duong (KB2, MR1)."
echo "   • Ngoai doi: mang ISP/BGP bat doi xung la binh thuong. Firewall stateful moi la thu can nhin."
