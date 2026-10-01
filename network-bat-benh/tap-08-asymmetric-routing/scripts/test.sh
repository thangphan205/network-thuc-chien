#!/usr/bin/env bash
# SMOKE TEST — chay 8 kich ban, khang dinh tung chu ky.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
HONG=0; PASS=0
kiem() { if [ "$2" = "$3" ]; then printf "   ✅ %s%*s %s\n" "$1" $((42 - ${#1})) "" "$2"; PASS=$((PASS+1)); else printf "   ❌ %s%*s %s   (mong đợi: %s)\n" "$1" $((42 - ${#1})) "" "$2" "$3"; HONG=$((HONG+1)); fi; }
reset() { luat_stateful $FWA; luat_stateful $FWB; dat_loose $FWA 0; dat_loose $FWB 0; xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB; docker exec $FWA iptables -t nat -F POSTROUTING >/dev/null 2>&1; }

echo "=============================================="
echo "🧪 TEST TẬP 08 — bảng vân tay của 8 kịch bản"
echo "=============================================="

echo ""; echo "KB1 — đường về đối xứng:"
server_ve a; reset
kiem "ping" "$(ping_thu)" "THONG"; kiem "curl http" "$(curl_thu)" "200"; kiem "fw-b gói INVALID" "$(so_invalid $FWB)" "0"

echo ""; echo "KB2 — ⭐ bất đối xứng + 2 stateful:"
server_ve b; reset
kiem "ping" "$(ping_thu)" "THONG"; kiem "curl http" "$(curl_thu)" "000"
kiem "fw-b có gói INVALID bị DROP" "$([ "$(so_invalid $FWB)" -gt 0 ] && echo CO || echo KHONG)" "CO"
kiem "fw-a có session SYN_SENT" "$(docker exec $FWA conntrack -L -p tcp --dport 80 2>/dev/null | grep -c SYN_SENT)" "1"

echo ""; echo "MR1 — ⭐⭐ fw-b permissive, fw-a vẫn stateful:"
server_ve b; reset; luat_permissive $FWB
kiem "curl http" "$(curl_thu)" "000"
kiem "fw-a có gói INVALID bị DROP" "$([ "$(so_invalid $FWA)" -gt 0 ] && echo CO || echo KHONG)" "CO"

echo ""; echo "MR2 — cả hai stateless:"
server_ve b; reset; luat_permissive $FWA; luat_permissive $FWB
kiem "curl http" "$(curl_thu)" "200"

echo ""; echo "MR3 — tcp_loose=1 không cứu:"
server_ve b; reset; dat_loose $FWA 1; dat_loose $FWB 1
kiem "curl http" "$(curl_thu)" "000"

echo ""; echo "MR4 — route flap giữa phiên:"
server_ve a; reset
( sleep 2; server_ve b ) & N=$(hai_get_giua_chung 5); wait
kiem "2 GET qua route flap" "$N" "1"
kiem "fw-b có gói INVALID bị DROP" "$([ "$(so_invalid $FWB)" -gt 0 ] && echo CO || echo KHONG)" "CO"

echo ""; echo "KB3 — chữa bằng SNAT:"
server_ve b; reset; docker exec $FWA iptables -t nat -A POSTROUTING -s $NET_C -d $NET_S -j MASQUERADE
kiem "curl http" "$(curl_thu)" "200"
kiem "fw-b gói INVALID" "$(so_invalid $FWB)" "0"
kiem "server thấy nguồn là fw-a" "$(docker logs --tail 1 $SERVER 2>&1 | grep -c "^$IP_FWA_S ")" "1"

echo ""; echo "MR5 — chữa bằng sửa route:"
server_ve b; reset; server_ve a
kiem "curl http" "$(curl_thu)" "200"
kiem "fw-b gói INVALID" "$(so_invalid $FWB)" "0"

echo ""; echo "🔧 Đưa lab về trạng thái bình thường..."
server_ve a; reset >/dev/null 2>&1
echo ""; echo "=============================================="
if [ "$HONG" -eq 0 ]; then
    echo "✅ TẤT CẢ $PASS PHÉP THỬ ĐỀU ĐÚNG."; exit 0
else
    echo "❌ $HONG PHÉP THỬ SAI (và $PASS đúng). Bảng vân tay trong README đang không khớp với lab."; exit 1
fi
