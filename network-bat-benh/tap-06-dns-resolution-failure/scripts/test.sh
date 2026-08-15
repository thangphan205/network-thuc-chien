#!/usr/bin/env bash
# Script test kiểm tra DNS và Ping
echo "=========================================="
echo "🩺 [BƯỚC 1] Ping trực tiếp qua IP (172.28.6.10):"
echo "=========================================="
docker compose exec client ping -c 2 172.28.6.10

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Kiểm tra file cấu hình DNS (/etc/resolv.conf):"
echo "=========================================="
docker compose exec client cat /etc/resolv.conf

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Phân giải tên miền 'web-server' (dig):"
echo "=========================================="
docker compose exec client dig +short web-server 2>&1

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 4] Truy cập Web bằng tên miền (curl):"
echo "=========================================="
docker compose exec client curl -Iv --connect-timeout 3 http://web-server 2>&1 | head -n 15
