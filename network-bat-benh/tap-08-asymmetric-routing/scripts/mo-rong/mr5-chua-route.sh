#!/usr/bin/env bash
# MR5 — Chua tan goc: sua route de duong ve DI QUA CUNG firewall voi duong di.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh
buoc "MR5 — sua route tren server: ve LAN client qua fw-a (cung firewall voi duong di)"
server_ve b; luat_stateful $FWA; luat_stateful $FWB; xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
echo "  TRUOC: server ve qua $(server_dang_ve) -> curl HTTP $(curl_thu)"
server_ve a; xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWB
echo "  SAU:   server ve qua $(server_dang_ve) -> curl HTTP $(curl_thu)   goi INVALID DROP o fw-b: $(so_invalid $FWB)"
echo ""
echo "👉 Doc chu ky:"
echo "   • Khong doi luat firewall nao. Chi doi mot dong route. fw-b tro lai 0 goi INVALID."
echo "   • Day la chua GOC. SNAT (KB3) chi la lam gia hai chieu de che loi nay."
