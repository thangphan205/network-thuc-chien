#!/usr/bin/env bash
# MR1 — ⭐⭐ fw-b "lanh tinh" (khong stateful) van chua du: fw-a stateful la du chet.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh
buoc "MR1 — duong ve bat doi xung, fw-b PERMISSIVE (cho qua het), fw-a van stateful"
server_ve b; luat_stateful $FWA; luat_permissive $FWB; dat_loose $FWA 0
xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
echo "  curl -> HTTP $(curl_thu)"
echo ""
echo "  fw-b: DROP nothing (permissive). fw-a:"
echo "     session port 80 = $(so_conntrack_80 $FWA)   goi INVALID DROP = $(so_invalid $FWA)"
docker exec $FWA conntrack -L -p tcp --dport 80 2>/dev/null | sed 's/^/     /' | cut -c1-150 | head -3
echo ""
echo "👉 Doc chu ky — SO VOI KB2:"
echo "   • Cung curl 000. Nhung THU PHAM DA DOI CHO: KB2 goi INVALID roi o fw-b,"
echo "     MR1 goi INVALID roi o fw-a."
echo "   • SYN-ACK di qua fw-b (cho qua) toi client. Client gui ACK hoan tat bat tay,"
echo "     ACK di qua fw-a — fw-a chua thay SYN-ACK -> coi ACK la INVALID -> DROP."
echo "   • Bai hoc: MOT thiet bi stateful tren mot trong hai duong la du de chet."
echo "     Sua 'fw-b' khong cuu duoc gi neu fw-a van stateful."
