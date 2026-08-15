#!/usr/bin/env bash
# Script test tu container Client (172.28.2.20) sang Web Server (172.28.2.10)
echo "=========================================="
echo "🩺 [BƯỚC 1] Bắt mạch L3: Kiểm tra Ping (172.28.2.10)..."
echo "=========================================="
docker compose exec client ping -c 3 172.28.2.10

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Bắt mạch L4: Kiểm tra Web (http://172.28.2.10)..."
echo "=========================================="
docker compose exec client curl -Iv http://172.28.2.10

echo ""
echo "=========================================="
