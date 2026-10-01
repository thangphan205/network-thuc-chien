#!/usr/bin/env bash
# KB3 — Chua bang SNAT tai fw-a: server tra loi ve DUNG fw-a du route van lech.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
buoc "KB3 — SNAT (MASQUERADE) tại fw-a, server VẪN về LAN client qua fw-b"
server_ve b; luat_stateful $FWA; luat_stateful $FWB; dat_loose $FWA 0; dat_loose $FWB 0
xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
docker exec $FWA iptables -t nat -A POSTROUTING -s $NET_C -d $NET_S -j MASQUERADE
echo "  server về LAN client qua : $(server_dang_ve)  (fw-b — KHÔNG SỬA route)"
echo "  ping -> $(ping_thu)   curl -> HTTP $(curl_thu)   gói INVALID DROP ở fw-b: $(so_invalid $FWB)"
echo ""
echo "  Nginx trên server thấy client là ai?"
docker logs --tail 1 $SERVER 2>&1 | cut -c1-60 | sed 's/^/     /'
docker exec $FWA iptables -t nat -F POSTROUTING
echo ""
echo "👉 Đọc chữ ký:"
echo "   • Server thấy nguồn là $IP_FWA_S (fw-a), không phải client. Gói trả lời gửi tới fw-a,"
echo "     mà fw-a nằm CÙNG LAN với server -> đi thẳng, không qua fw-b."
echo "   • Giải pháp khi KHÔNG được sửa route (ISP/đối tác nằm giữa). Cái giá: server mất IP thật của client."
