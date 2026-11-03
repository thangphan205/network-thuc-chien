#!/usr/bin/env bash
# ==============================================================================
# SMOKE TEST — chay KB1, KB2 + thuoc va khang dinh tung chu ky.
#
#   ./scripts/test.sh
#
# Vi sao can file nay?
#   Vi bai hoc cua tap la mot BANG SO. Neu mot ban kernel nao do doi hanh vi
#   conntrack (vd loose mode), README se day sai ma khong
#   ai biet. File nay bat duoc dieu do ngay.
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

HONG=0
PASS=0

kiem() {   # kiem <ten> <thuc_te> <mong_doi>
    if [ "$2" = "$3" ]; then
        printf "   ✅ %s%*s %s\n" "$1" $((40 - ${#1})) "" "$2"
        PASS=$((PASS + 1))
    else
        printf "   ❌ %s%*s %s   (mong đợi: %s)\n" "$1" $((40 - ${#1})) "" "$2" "$3"
        HONG=$((HONG + 1))
    fi
}

echo "=============================================="
echo "🧪 TEST TẬP 07 — bảng vân tay KB1, KB2 và thuốc"
echo "=============================================="

echo ""
echo "KB1 — bình thường (timeout mặc định):"
dat_tcp_timeout 432000; dat_loose 0
kiem "2 GET qua idle 12s" "$(hai_get_qua_idle 12)" "2"

echo ""
echo "KB2 — ⭐ NAT xóa phiên im lặng (timeout=10s loose=0):"
dat_tcp_timeout 10; dat_loose 0
kiem "2 GET qua idle 12s" "$(hai_get_qua_idle 12)" "1"

echo ""
echo "KB2 với tcp_loose=1 (mặc định Linux, README dựa vào kết quả này):"
dat_tcp_timeout 10; dat_loose 1
kiem "2 GET qua idle 12s" "$(hai_get_qua_idle 12)" "2"

echo ""
echo "KB2 (thuốc) — ⭐ keepalive cứu sống (NAT timeout=10s, keepidle=2s):"
dat_tcp_timeout 10; dat_loose 0
N=$(docker exec $CLIENT sh -c "
  { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
    sleep 12;
    printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
    sleep 2; } | socat -t 15 - TCP:$IP_SERVER:80,keepalive,keepidle=2,keepintvl=2,keepcnt=3 | grep -c '^HTTP/1.1 200'
" 2>/dev/null | tr -d ' \r')
kiem "2 GET qua idle 12s (có keepalive)" "$N" "2"

echo ""
echo "KB2 (thuốc sai liều) — NAT timeout=10s, keepidle=20s > 10s, README dựa vào kết quả này:"
N=$(docker exec $CLIENT sh -c "
  { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
    sleep 12;
    printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
    sleep 2; } | socat -t 15 - TCP:$IP_SERVER:80,keepalive,keepidle=20,keepintvl=20,keepcnt=3 | grep -c '^HTTP/1.1 200'
" 2>/dev/null | tr -d ' \r')
kiem "2 GET qua idle 12s (keepalive sai liều)" "$N" "1"

echo ""
echo "🔧 Đưa lab về trạng thái bình thường..."
dat_tcp_timeout 432000 >/dev/null; dat_loose 0 >/dev/null

echo ""
echo "=============================================="
if [ "$HONG" -eq 0 ]; then
    echo "✅ TẤT CẢ $PASS PHÉP THỬ ĐỀU ĐÚNG."
    exit 0
else
    echo "❌ $HONG PHÉP THỬ SAI (và $PASS đúng)."
    echo "   Bảng vân tay trong README đang không khớp với lab — sửa trước khi dạy."
    exit 1
fi
