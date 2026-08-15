#!/usr/bin/env bash
# Script test kiểm tra bảng Route và Ping LAN vs Internet
echo "=========================================="
echo "🩺 [BƯỚC 1] Soi bảng định tuyến trên Client (ip route show):"
echo "=========================================="
docker compose exec client apk add --no-cache iputils iproute2 >/dev/null 2>&1
docker compose exec client ip route show

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Ping máy chủ CÙNG MẠNG LAN (172.28.12.10):"
echo "=========================================="
docker compose exec client ping -c 2 172.28.12.10

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Ping địa chỉ NGOÀI INTERNET (1.1.1.1):"
echo "=========================================="
docker compose exec client ping -c 2 1.1.1.1 2>&1

echo ""
echo "=========================================="
