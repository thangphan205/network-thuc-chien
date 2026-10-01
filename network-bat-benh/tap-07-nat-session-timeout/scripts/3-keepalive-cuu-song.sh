#!/usr/bin/env bash
# ==============================================================================
# KB3 — ⭐ Chua dung: TCP keepalive cuu song phien qua NAT timeout ngan
#
# Van giu NAT established timeout = 5s (nguy hiem nhu KB2). Nhung lan nay
# CLIENT tu mo ket noi voi SO_KEEPALIVE + keepidle=2s < 5s. Cu 2 giay client
# gui mot goi ACK rong -- goi do di qua gateway, LAM MOI dong ho conntrack --
# session khong bao gio kip het han.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

buoc "KB3 — NAT timeout=5s (vẫn nguy hiểm), nhưng CLIENT bật TCP keepalive idle=2s"
dat_tcp_timeout 5
dat_loose 0
dat_nginx dai

echo "  Bắt gói trên gateway để thấy CÁC PROBE keepalive thật (terminal ẩn)..."
docker exec -d $GATEWAY sh -c "timeout 12 tcpdump -i any -n 'tcp port 80 and tcp[13]==0x10' -w /tmp/ka.pcap >/dev/null 2>&1"
sleep 1

echo "  Mở kết nối bằng keepalive (keepidle=2 keepintvl=2 keepcnt=3), idle 7s, GET #2:"
N=$(docker exec $CLIENT sh -c "
  { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
    sleep 7;
    printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
    sleep 2; } | socat -t 15 - TCP:$IP_SERVER:80,keepalive,keepidle=2,keepintvl=2,keepcnt=3 | grep -c '^HTTP/1.1 200'
" 2>/dev/null | tr -d ' \r')
echo "  👉 Số phản hồi HTTP 200 nhận được: ${N}/2   (KB2 cùng idle 7s, cùng timeout 5s -> chỉ 1/2)"
sleep 1
echo ""
echo "  Các probe keepalive thực sự đi qua gateway (pure ACK, length 0, cách nhau ~2s):"
docker exec $GATEWAY sh -c "tcpdump -r /tmp/ka.pcap -n 2>/dev/null | grep 'eth0  In'" | sed 's/^/     /'
echo ""
echo "👉 Đọc chữ ký:"
echo "   • ${N}/2 — GIỐNG HỆT môi trường nguy hiểm của KB2 (timeout=5s, idle=7s)"
echo "     chỉ khác MỘT thứ: keepalive. Đó là bằng chứng 'thuốc' có thật."
echo "   • Mỗi probe là một gói ACK RỖNG (length 0) — nó LÀM MỚI đồng hồ"
echo "     ESTABLISHED của conntrack tại gateway, đúng như một gói dữ liệu thật."
echo "   • ⚠️ Điều kiện BẮT BUỘC: keepidle PHẢI NHỎ HƠN established timeout của"
echo "     NAT. Xem MR4 để thấy chuyện gì xảy ra khi điều kiện này bị vi phạm."
