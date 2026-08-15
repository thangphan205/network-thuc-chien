#!/usr/bin/env bash
# Script test so sánh giữa Localhost và Remote Client
echo "=========================================="
echo "🩺 [TEST 1] Đứng TẠI SERVER curl 127.0.0.1:"
echo "=========================================="
docker compose exec web-server curl -I http://127.0.0.1

echo ""
echo "=========================================="
echo "🩺 [TEST 2] Soi Socket Listening trên Server (ss -tulpn):"
echo "=========================================="
docker compose exec web-server netstat -tulpn 2>/dev/null || docker compose exec web-server ss -tulpn

echo ""
echo "=========================================="
echo "🩺 [TEST 3] Đứng từ CLIENT (172.28.3.20) curl sang SERVER (172.28.3.10):"
echo "=========================================="
docker compose exec client curl -Iv http://172.28.3.10
