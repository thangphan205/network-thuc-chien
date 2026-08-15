#!/usr/bin/env bash
# Script test tu container Client (172.28.1.20) sang Web Server (172.28.1.10)
echo "=========================================="
echo "🩺 [BƯỚC 1] Bắt mạch L3: Kiểm tra Ping (172.28.1.10)..."
echo "=========================================="
docker compose exec client ping -c 3 172.28.1.10

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Bắt mạch L4/L7: Kiểm tra Web (http://172.28.1.10)..."
echo "=========================================="
docker compose exec client curl -Iv --connect-timeout 4 http://172.28.1.10

echo ""
echo "=========================================="
