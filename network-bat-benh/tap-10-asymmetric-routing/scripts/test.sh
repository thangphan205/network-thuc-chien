#!/usr/bin/env bash
# Script test kiểm tra Ping vs TCP kết nối
echo "=========================================="
echo "🩺 [BƯỚC 1] Kiểm tra Ping 2 chiều từ Client sang Server:"
echo "=========================================="
docker compose exec client apk add --no-cache iputils curl >/dev/null 2>&1
docker compose exec client ping -c 3 172.28.10.10

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Kiểm tra kết nối Web TCP (curl):"
echo "=========================================="
docker compose exec client curl -Iv --connect-timeout 4 http://172.28.10.10 2>&1 | head -n 20

echo ""
echo "=========================================="
