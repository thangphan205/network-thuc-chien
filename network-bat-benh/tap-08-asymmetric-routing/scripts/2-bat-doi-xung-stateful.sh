#!/usr/bin/env bash
# KB2 — ⭐ Bat doi xung + 2 firewall stateful: SYN qua fw-a, SYN-ACK ve qua fw-b.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
buoc "KB2 — server về LAN client qua fw-b (BẤT ĐỐI XỨNG), cả hai firewall stateful"
server_ve b; luat_stateful $FWA; luat_stateful $FWB; dat_loose $FWA 0; dat_loose $FWB 0
xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
echo "  server về LAN client qua : $(server_dang_ve)  (fw-b)"
echo "  ping -> $(ping_thu)"
echo "  curl -> HTTP $(curl_thu)  (000 = không bắt tay xong)"
echo ""
echo "  fw-a — SYN đi qua đây, nhưng SYN-ACK không bao giờ về:"
docker exec $FWA conntrack -L -p tcp --dport 80 2>/dev/null | sed 's/^/     /' | cut -c1-150 | head -3
echo "  fw-b — chưa từng thấy SYN:  session port 80 = $(so_conntrack_80 $FWB)   gói INVALID DROP = $(so_invalid $FWB)"
echo ""
echo "👉 Đọc chữ ký:"
echo "   • ping THÔNG (ICMP không cần trạng thái), curl 000: TCP chết ở bước bắt tay."
echo "   • fw-a: SYN_SENT [UNREPLIED] — nó thấy SYN, chưa bao giờ thấy SYN-ACK."
echo "   • fw-b: 0 session + counter INVALID tăng — SYN-ACK của một kết nối nó chưa từng thấy."
echo "   • Không có gì hỏng ở server, ở client hay ở từng firewall riêng lẻ."
