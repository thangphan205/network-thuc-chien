#!/usr/bin/env bash
# KB1 — Trang thai khoe: SYN va SYN-ACK cung di qua fw-a. Moc so sanh.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
buoc "KB1 — đường về ĐỐI XỨNG (server về qua fw-a)"
server_ve a; luat_stateful $FWA; luat_stateful $FWB; dat_loose $FWA 0; dat_loose $FWB 0
xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
echo "  server về LAN client qua : $(server_dang_ve)  (fw-a)"
echo "  ping -> $(ping_thu)"
echo "  curl -> HTTP $(curl_thu)"
echo "  fw-a session port 80: $(so_conntrack_80 $FWA)   fw-b session port 80: $(so_conntrack_80 $FWB)   gói INVALID DROP ở fw-b: $(so_invalid $FWB)"
echo "👉 Ghi lại: ping THÔNG, curl 200, fw-b KHÔNG thấy gì (0 session, 0 INVALID)."
