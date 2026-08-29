#!/usr/bin/env bash
# Test so sánh Ping gói nhỏ vs Ping gói lớn (DF set) và Tải Web qua Router
echo "=========================================="
echo "🩺 [TEST 1] Ping gói nhỏ tiêu chuẩn (64 bytes) từ Client -> Server:"
echo "=========================================="
docker compose exec client ping -c 3 172.28.42.10

echo ""
echo "=========================================="
echo "🩺 [TEST 2] Ping gói lớn kèm cờ Don't Fragment (1450 bytes):"
echo "=========================================="
docker compose exec client ping -c 2 -s 1450 -M do 172.28.42.10 || true

echo ""
echo "=========================================="
echo "🩺 [TEST 3] Tải trang Web từ Web Server (curl qua Router):"
echo "=========================================="
docker compose exec client curl -sS -o /dev/null -w "HTTP %{http_code} | tải về %{size_download} bytes | %{time_total}s\n" --connect-timeout 3 --max-time 6 http://172.28.42.10 \
  || echo "❌ curl treo/timeout — body không về được do MTU Blackhole!"
