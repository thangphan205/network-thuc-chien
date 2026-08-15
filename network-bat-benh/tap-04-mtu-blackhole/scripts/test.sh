#!/usr/bin/env bash
# Script test so sánh giữa Ping gói nhỏ vs Ping gói lớn và Tải Web
echo "=========================================="
echo "🩺 [TEST 1] Ping gói nhỏ tiêu chuẩn (64 bytes):"
echo "=========================================="
docker compose exec client ping -c 3 172.28.4.10

echo ""
echo "=========================================="
echo "🩺 [TEST 2] Ping gói lớn với cờ Don't Fragment (1400 bytes):"
echo "=========================================="
docker compose exec client ping -c 3 -s 1400 -M do 172.28.4.10

echo ""
echo "=========================================="
echo "🩺 [TEST 3] Tải trang Web dung lượng lớn (curl):"
echo "=========================================="
docker compose exec client curl -sS -o /dev/null -w "HTTP %{http_code} | tải về %{size_download} bytes | %{time_total}s\n" --connect-timeout 4 --max-time 8 http://172.28.4.10 \
  || echo "❌ curl treo/đứt giữa chừng — đúng triệu chứng MTU Blackhole!"
