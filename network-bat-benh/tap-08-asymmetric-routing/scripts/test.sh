#!/usr/bin/env bash
# ==============================================================================
# SMOKE TEST — chay KB1, KB2 + 2 thuoc (2a, 2b) va cac bay thuong gap,
# khang dinh tung chu ky trong README.
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
HONG=0; PASS=0
kiem() {
    if [ "$2" = "$3" ]; then
        printf "   ✅ %s%*s %s\n" "$1" $((42 - ${#1})) "" "$2"
        PASS=$((PASS+1))
    else
        printf "   ❌ %s%*s %s   (mong đợi: %s)\n" "$1" $((42 - ${#1})) "" "$2" "$3"
        HONG=$((HONG+1))
    fi
}
reset() {
    unset _DA_CHO_SYNACK   # cho SYN-ACK gui lai cua ca truoc tat han, moi ca mot lan
    luat_stateful $FWA; luat_stateful $FWB
    dat_loose $FWA 0; dat_loose $FWB 0
    xoa_conntrack $FWA; xoa_conntrack $FWB
    zero_dem $FWA; zero_dem $FWB
    docker exec $FWA iptables -t nat -F POSTROUTING >/dev/null 2>&1
}

echo "=============================================="
echo "🧪 TEST TẬP 08 — bảng vân tay KB1, KB2 và thuốc"
echo "=============================================="

echo ""; echo "KB1 — đường về đối xứng (mốc khỏe):"
server_ve a; reset
kiem "ping" "$(ping_thu)" "THONG"
kiem "curl http" "$(curl_thu)" "200"
kiem "fw-b gói INVALID" "$(so_invalid $FWB)" "0"

echo ""; echo "KB2 — ⭐ bất đối xứng + 2 firewall stateful:"
server_ve b; reset
kiem "ping" "$(ping_thu)" "THONG"
kiem "ping server->client" "$(ping_nguoc)" "THONG"
kiem "curl http" "$(curl_thu)" "000"
kiem "curl -v không có dòng Connected" "$(curl_chi_tiet | grep -c Connected)" "0"
kiem "fw-b có gói INVALID bị DROP" "$([ "$(so_invalid $FWB)" -gt 0 ] && echo CO || echo KHONG)" "CO"
kiem "fw-a có session SYN_SENT" "$([ "$(docker exec $FWA conntrack -L -p tcp --dport 80 2>/dev/null | grep -c SYN_SENT)" -ge 1 ] && echo CO || echo KHONG)" "CO"

echo ""; echo "Thuốc 2a — ⭐ chữa gốc bằng sửa route:"
server_ve b; reset; server_ve a
kiem "curl http" "$(curl_thu)" "200"
kiem "fw-b gói INVALID" "$(so_invalid $FWB)" "0"
kiem "server thấy IP thật của client" "$(docker logs --tail 1 $SERVER 2>&1 | grep -c "^$IP_CLIENT ")" "1"

echo ""; echo "Thuốc 2b — chữa tình thế bằng SNAT tại fw-a:"
server_ve b; reset
docker exec $FWA iptables -t nat -A POSTROUTING -s $NET_C -d $NET_S -j MASQUERADE
kiem "curl http" "$(curl_thu)" "200"
kiem "fw-b gói INVALID" "$(so_invalid $FWB)" "0"
kiem "server thấy nguồn là fw-a" "$(docker logs --tail 1 $SERVER 2>&1 | grep -c "^$IP_FWA_S ")" "1"

echo ""; echo "Bẫy 1 (README) — mở thông fw-b (permissive), fw-a vẫn DROP ACK:"
server_ve b; reset; luat_permissive $FWB
kiem "curl http" "$(curl_thu)" "000"
kiem "curl -v CÓ dòng Connected (khác KB2)" "$(curl_chi_tiet | grep -c Connected)" "1"
kiem "fw-a có gói INVALID bị DROP" "$([ "$(so_invalid $FWA)" -gt 0 ] && echo CO || echo KHONG)" "CO"

echo ""; echo "Bẫy 2 (README) — tcp_loose=1 không cứu được SYN-ACK mở đầu:"
server_ve b; reset; dat_loose $FWA 1; dat_loose $FWB 1
kiem "curl http" "$(curl_thu)" "000"
kiem "fw-b có gói INVALID bị DROP" "$([ "$(so_invalid $FWB)" -gt 0 ] && echo CO || echo KHONG)" "CO"
kiem "fw-a gói INVALID" "$(so_invalid $FWA)" "0"

echo ""; echo "🔧 Đưa lab về trạng thái bình thường..."
server_ve a; reset >/dev/null 2>&1
echo ""; echo "=============================================="
if [ "$HONG" -eq 0 ]; then
    echo "✅ TẤT CẢ $PASS PHÉP THỬ ĐỀU ĐÚNG."; exit 0
else
    echo "❌ $HONG PHÉP THỬ SAI (và $PASS đúng). Bảng vân tay trong README đang không khớp với lab."; exit 1
fi
