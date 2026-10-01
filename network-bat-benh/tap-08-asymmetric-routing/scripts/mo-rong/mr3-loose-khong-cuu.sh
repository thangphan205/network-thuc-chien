#!/usr/bin/env bash
# MR3 — tcp_loose=1 KHONG cuu duoc (doi lap voi tap 07 MR1).
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh
buoc "MR3 — bat doi xung, ca hai firewall stateful, tcp_loose=1 tren CA HAI"
server_ve b; luat_stateful $FWA; luat_stateful $FWB; dat_loose $FWA 1; dat_loose $FWB 1
xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
echo "  tcp_loose: fw-a=$(docker exec $FWA sysctl -n net.netfilter.nf_conntrack_tcp_loose)  fw-b=$(docker exec $FWB sysctl -n net.netfilter.nf_conntrack_tcp_loose)"
echo "  curl -> HTTP $(curl_thu)"
dat_loose $FWA 0; dat_loose $FWB 0
echo ""
echo "👉 Doc chu ky:"
echo "   • Van 000. Tap 09 MR1: tcp_loose=1 'tha' duoc goi giua chung nen ca benh idle bien mat."
echo "   • O day khong cuu duoc: loose mode chi 'nhat' goi vao KHI phien DA ton tai va bi mat"
echo "     entry. Bat doi xung la phien CHUA TUNG duoc thay du ca hai chieu tu luc bat tay."
echo "   • Khong co nut tat nhanh nao o firewall. Chua phai sua duong di hoac SNAT (KB3, MR5)."
