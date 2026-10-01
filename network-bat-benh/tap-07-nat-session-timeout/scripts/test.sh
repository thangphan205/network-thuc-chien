#!/usr/bin/env bash
# ==============================================================================
# SMOKE TEST — chay ca 7 kich ban va khang dinh tung ca ra DUNG chu ky mong doi.
#
#   ./scripts/test.sh
#
# Vi sao can file nay?
#   Vi bai hoc cua tap la mot BANG SO. Neu mot ban kernel nao do doi hanh vi
#   conntrack (vd loose mode, UDP NEW-vs-INVALID), README se day sai ma khong
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
echo "🧪 TEST TẬP 07 — bảng vân tay của 7 kịch bản"
echo "=============================================="

echo ""
echo "KB1 — bình thường (mặc định kernel, chưa đụng gì):"
dat_tcp_timeout 432000; dat_loose 0; dat_udp_timeout 30; dat_nginx dai
kiem "2 GET qua idle 7s" "$(hai_get_qua_idle 7)" "2"

echo ""
echo "KB2 — ⭐ NAT xóa phiên im lặng (timeout=5s loose=0):"
dat_tcp_timeout 5; dat_loose 0
kiem "2 GET qua idle 7s" "$(hai_get_qua_idle 7)" "1"

echo ""
echo "MR1 — NAT "tha" gói giữa chừng (timeout=5s loose=1):"
dat_tcp_timeout 5; dat_loose 1
kiem "2 GET qua idle 7s" "$(hai_get_qua_idle 7)" "2"

echo ""
echo "MR2 — UDP tự làm mới (udp timeout=5s, idle=7s vượt):"
dat_tcp_timeout 432000; dat_loose 0; dat_udp_timeout 5
kiem "số byte echo (2 gói)" "$(hai_goi_udp_qua_idle 7)" "8"
dat_udp_timeout 30

echo ""
echo "MR3 — ⭐⭐ server tự đóng (keepalive_timeout=3s, NAT timeout dài):"
dat_tcp_timeout 432000; dat_loose 0; dat_nginx ngan
kiem "2 GET qua idle 7s" "$(hai_get_qua_idle 7)" "1"
dat_nginx dai

echo ""
echo "KB3 — ⭐ keepalive cứu sống (NAT timeout=5s, keepidle=2s):"
dat_tcp_timeout 5; dat_loose 0
N=$(docker exec $CLIENT sh -c "
  { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
    sleep 7;
    printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
    sleep 2; } | socat -t 15 - TCP:$IP_SERVER:80,keepalive,keepidle=2,keepintvl=2,keepcnt=3 | grep -c '^HTTP/1.1 200'
" 2>/dev/null | tr -d ' \r')
kiem "2 GET qua idle 7s (có keepalive)" "$N" "2"

echo ""
echo "MR4 — keepalive interval sai (NAT timeout=5s, keepidle=10s > 5s):"
N=$(docker exec $CLIENT sh -c "
  { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
    sleep 7;
    printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
    sleep 2; } | socat -t 15 - TCP:$IP_SERVER:80,keepalive,keepidle=10,keepintvl=10,keepcnt=3 | grep -c '^HTTP/1.1 200'
" 2>/dev/null | tr -d ' \r')
kiem "2 GET qua idle 7s (keepalive sai liều)" "$N" "1"

echo ""
echo "🔧 Đưa lab về trạng thái bình thường..."
dat_tcp_timeout 432000 >/dev/null; dat_loose 0 >/dev/null; dat_udp_timeout 30 >/dev/null; dat_nginx dai >/dev/null

echo ""
echo "=============================================="
if [ "$HONG" -eq 0 ]; then
    echo "✅ TẤT CẢ $PASS PHÉP THỬ ĐỀU ĐÚNG."
    echo ""
    echo "   ⭐⭐ Cặp đáng giá nhất vừa chạy qua:"
    echo "        KB2  NAT xóa, im lặng, client tự chờ hết timeout (~23s)"
    echo "        MR3  server tự FIN, có báo, đóng ngay (~10s)"
    exit 0
else
    echo "❌ $HONG PHÉP THỬ SAI (và $PASS đúng)."
    echo "   Bảng vân tay trong README đang không khớp với lab — sửa trước khi dạy."
    exit 1
fi
