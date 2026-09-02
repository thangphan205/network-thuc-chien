#!/usr/bin/env bash
# Chứng minh: GARP là BROADCAST, nó dừng lại ở biên L3.
# Bắt ARP đồng thời ở CLIENT (subnet 6) và ROUTER chân server (subnet 7),
# rồi phát GARP từ node-b. Router nhận đủ, client không thấy gói nào.
# Chạy sau 1-fault.sh.
set -e
cd "$(dirname "$0")/.."
source scripts/_lib.sh
SRV_IF=$(r_srv_if)

echo "📡 Bắt ARP ở CLIENT (eth0, subnet 172.28.6) và ROUTER ($SRV_IF, subnet 172.28.7)..."
docker compose exec -d client tcpdump -i eth0 -n -e arp -w /tmp/c.pcap
docker compose exec -d router tcpdump -i "$SRV_IF" -n -e arp -w /tmp/r.pcap
sleep 2

echo "📢 node-b phát GARP..."
docker compose exec node-b arping -U -c 3 -I eth0 $VIP >/dev/null
sleep 2
docker compose exec client pkill tcpdump || true
docker compose exec router pkill tcpdump || true
sleep 1

echo ""
echo "[ROUTER — chân phía server] nhận được:"
docker compose exec router tcpdump -n -e -r /tmp/r.pcap 2>&1 | grep -v '^reading' | sed 's/^/   /'
echo ""
echo "[CLIENT — khác subnet] nhận được:"
CLIENT_ARP=$(docker compose exec client tcpdump -n -e -r /tmp/c.pcap 2>&1 | grep -v '^reading' | grep "$VIP" || true)
if [ -n "$CLIENT_ARP" ]; then
  echo "$CLIENT_ARP" | sed 's/^/   /'
else
  echo "   (KHÔNG một gói GARP nào — broadcast dừng lại ở biên L3)"
fi

docker compose exec client rm -f /tmp/c.pcap
docker compose exec router rm -f /tmp/r.pcap

echo ""
echo "🔑 GARP chỉ đi trong đúng subnet của VIP. Nó KHÔNG cần và KHÔNG THỂ tới client."
echo "   May thay, router có chân trong subnet đó — nên vẫn nghe được. Đó là lý do"
echo "   một lệnh arping trên node-b vẫn chữa được cho toàn bộ client ở mọi subnet."
