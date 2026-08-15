#!/usr/bin/env bash
# Mô phỏng đúng ca bệnh: 1 kết nối TCP duy nhất -> request 1 OK -> idle 7 giây -> request 2
echo "=========================================="
echo "🩺 [BƯỚC 1] Giá trị Idle Timeout hiện tại trên 'NAT Gateway':"
echo "=========================================="
docker compose exec server sysctl net.netfilter.nf_conntrack_tcp_timeout_established

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Mở 1 kết nối TCP: GET #1 -> idle 7 giây -> GET #2 (cùng kết nối):"
echo "   Khi bệnh ACTIVE: chỉ nhận được 1/2 phản hồi — GET #2 bị nuốt im lặng."
echo "=========================================="
N=$(docker compose exec client sh -c '
  { printf "GET / HTTP/1.1\r\nHost: 172.28.9.10\r\nConnection: keep-alive\r\n\r\n";
    sleep 7;
    printf "GET / HTTP/1.1\r\nHost: 172.28.9.10\r\nConnection: close\r\n\r\n";
    sleep 3; } | nc -w 12 172.28.9.10 80 | grep -c "HTTP/1.1 200"
' | tr -d '\r')
echo "👉 Số phản hồi HTTP 200 nhận được trên 1 kết nối: ${N:-0}/2"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Soi bảng conntrack trên server (session của client còn hay đã bị xóa?):"
echo "=========================================="
docker compose exec server sh -c '
  echo "Số session đang theo dõi: $(sysctl -n net.netfilter.nf_conntrack_count)"
  cat /proc/net/nf_conntrack 2>/dev/null | grep "dport=80" || echo "(không còn session port 80 nào trong bảng — firewall đã xóa phiên!)"
'
