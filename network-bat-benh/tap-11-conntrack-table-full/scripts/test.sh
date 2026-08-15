#!/usr/bin/env bash
# Script test kiểm tra trạng thái bảng Conntrack
echo "=========================================="
echo "🩺 [BƯỚC 1] Soi số lượng kết nối hiện tại vs Giới hạn Max:"
echo "=========================================="
docker compose exec server sh -c "echo 'Conntrack Count:' \$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo 'N/A') && echo 'Conntrack Max:  ' \$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 'N/A')"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Bơm tải hàng loạt request từ Client:"
echo "=========================================="
docker compose exec client apk add --no-cache curl apache2-utils >/dev/null 2>&1
docker compose exec client ab -n 30 -c 10 http://172.28.11.10/ 2>&1 | grep -E "Complete requests|Failed requests|Non-2xx responses"

echo ""
echo "=========================================="
