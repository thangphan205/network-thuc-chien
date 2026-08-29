#!/usr/bin/env bash
# Tự động bắt gói tin trên Router để mở bằng Wireshark
set -e
echo "🦈 Đang bắt gói tin trên interface của Router (tcp port 80 or icmp)..."

docker compose exec router pkill tcpdump 2>/dev/null || true
docker compose exec -d router tcpdump -i any -s 0 -w /tmp/router.pcap -n "tcp port 80 or icmp"
sleep 2

echo "🌐 Đang thực hiện curl từ Client -> Server..."
docker compose exec client curl -sS -o /dev/null --connect-timeout 3 --max-time 5 http://172.28.42.10 || true
sleep 2

docker compose exec router pkill -2 tcpdump 2>/dev/null || true
sleep 1
docker compose cp router:/tmp/router.pcap ./router.pcap

echo "✅ Đã lưu file bắt gói tại: ./router.pcap"
echo "👉 Mở file ./router.pcap bằng Wireshark để xem gói SYN MSS, ICMP Frag Needed hoặc TCP Retransmission!"
