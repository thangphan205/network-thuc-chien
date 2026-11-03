#!/usr/bin/env bash
# ==============================================================================
# KB2 (thuoc) — ⭐ Chua dung: TCP keepalive cuu song phien qua NAT timeout ngan
#
# Van giu NAT established timeout = 10s (nguy hiem nhu KB2). Nhung lan nay
# CLIENT tu mo ket noi voi SO_KEEPALIVE + keepidle=2s < 10s. Cu 2 giay client
# gui mot goi ACK rong -- goi do di qua gateway, LAM MOI dong ho conntrack --
# session khong bao gio kip het han.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

buoc "KB2 (thuốc) — NAT timeout=10s (vẫn nguy hiểm), nhưng CLIENT bật TCP keepalive idle=2s"
dat_tcp_timeout 10
dat_loose 0

echo "  Bắt gói trên gateway để thấy CÁC PROBE keepalive thật (terminal ẩn)..."
docker exec -d $GATEWAY sh -c "timeout 18 tcpdump -i any -n 'tcp port 80 and tcp[13]==0x10' -w /tmp/ka.pcap >/dev/null 2>&1"
sleep 1

echo "  Mở kết nối bằng keepalive (keepidle=2 keepintvl=2 keepcnt=3), idle 12s, GET #2:"
N=$(docker exec $CLIENT sh -c "
  { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
    sleep 12;
    printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
    sleep 2; } | socat -t 15 - TCP:$IP_SERVER:80,keepalive,keepidle=2,keepintvl=2,keepcnt=3 | grep -c '^HTTP/1.1 200'
" 2>/dev/null | tr -d ' \r')
echo "  👉 Số phản hồi HTTP 200 nhận được: ${N}/2   (KB2 cùng idle 12s, cùng timeout 10s -> chỉ 1/2)"
sleep 1
echo ""
echo "  Các probe keepalive thực sự đi qua gateway (pure ACK, length 0, cách nhau ~2s):"
docker exec $GATEWAY sh -c "tcpdump -r /tmp/ka.pcap -n 2>/dev/null | grep 'eth0  In'" | sed 's/^/     /'
echo ""
echo "👉 Đọc chữ ký:"
echo "   • ${N}/2 — GIỐNG HỆT môi trường nguy hiểm của KB2 (timeout=10s, idle=12s)"
echo "     chỉ khác MỘT thứ: keepalive. Đó là bằng chứng 'thuốc' có thật."
echo "   • Mỗi probe là một gói ACK RỖNG (length 0) — nó LÀM MỚI đồng hồ"
echo "     ESTABLISHED của conntrack tại gateway, đúng như một gói dữ liệu thật."
echo "   • ⚠️ Điều kiện BẮT BUỘC: keepidle PHẢI NHỎ HƠN established timeout của"
echo "     NAT, nếu không thì phiên vẫn đứt như chưa bật keepalive."
