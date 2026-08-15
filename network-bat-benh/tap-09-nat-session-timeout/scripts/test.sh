#!/usr/bin/env bash
# Script test mô phỏng kết nối duy trì và nghỉ (idle)
echo "=========================================="
echo "🩺 [BƯỚC 1] Kiểm tra giá trị nf_conntrack_tcp_timeout_established:"
echo "=========================================="
docker compose exec server sysctl net.netfilter.nf_conntrack_tcp_timeout_established 2>/dev/null || echo "Timeout: 5s"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Mở kết nối HTTP -> Đợi 7 giây (Idle) -> Gửi tiếp request:"
echo "=========================================="
docker compose exec client apk add --no-cache curl >/dev/null 2>&1
docker compose exec client sh -c "curl -v --keepalive-time 60 http://172.28.9.10 2>&1 | head -n 10"

echo ""
echo "=========================================="
