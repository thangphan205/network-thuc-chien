#!/usr/bin/env bash
# Script test so sánh giữa Localhost và Remote Client.
# Không dùng `set -e`: TEST 3 fail là hành vi MONG ĐỢI khi đang ở trạng thái bệnh.
cd "$(dirname "$0")/.."

echo "=========================================="
echo "🩺 [TEST 1] Đứng TẠI SERVER curl 127.0.0.1:"
echo "=========================================="
docker compose exec web-server curl -sS -I http://127.0.0.1

echo ""
echo "=========================================="
echo "🩺 [TEST 2] Soi Socket Listening trên Server (ss -tulpn):"
echo "=========================================="
docker compose exec web-server ss -tulpn | grep -E 'Local Address|:80'

echo ""
echo "=========================================="
echo "🩺 [TEST 3] Đứng từ CLIENT (172.28.3.20) curl sang SERVER (172.28.3.10):"
echo "=========================================="
docker compose exec client curl -Iv http://172.28.3.10

echo ""
echo "=========================================="
echo "🩺 [TEST 4] Bắt gói tin trên CLIENT: SYN đi ra, cờ gì đi về?"
echo "=========================================="
docker compose exec -d client sh -c 'tcpdump -i eth0 -n -l "tcp port 80" > /tmp/cap03.txt 2>&1'
sleep 1
docker compose exec client curl -s -m 3 -o /dev/null http://172.28.3.10
sleep 1
docker compose exec client pkill tcpdump
docker compose exec client grep -E 'Flags' /tmp/cap03.txt
