#!/usr/bin/env bash
# Script test so sánh giữa Ping gói nhỏ vs Ping gói lớn và Tải Web
echo "=========================================="
echo "🩺 [TEST 1] Ping gói nhỏ tiêu chuẩn (64 bytes):"
echo "=========================================="
ping -c 3 127.0.0.1

echo ""
echo "=========================================="
echo "🩺 [TEST 2] Ping gói lớn với cờ Don't Fragment (1400 bytes):"
echo "=========================================="
docker compose exec client apk add --no-cache iputils curl >/dev/null 2>&1
docker compose exec client ping -c 3 -s 1400 -M do 172.28.4.10 2>/dev/null || ping -c 3 -s 1400 127.0.0.1

echo ""
echo "=========================================="
echo "🩺 [TEST 3] Tải trang Web dung lượng lớn (curl):"
echo "=========================================="
docker compose exec client curl -v --connect-timeout 4 --max-time 6 http://172.28.4.10 2>&1 | head -n 30

echo ""
echo "=========================================="
