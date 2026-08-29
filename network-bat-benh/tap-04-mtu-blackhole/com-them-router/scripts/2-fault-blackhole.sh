#!/usr/bin/env bash
# Kịch bản 2: Kích hoạt MTU Blackhole trên Router (Firewall chặn ICMP Type 3 Code 4)
set -e
echo "🚨 [KỊCH BẢN 2] Kích hoạt lỗi MTU Blackhole trên Router..."

# Reset mangle chain (tắt MSS Clamping nếu có từ trước)
docker compose exec router iptables -t mangle -F

# Thiết lập MTU 1400 trên phân đoạn định tuyến của Router
docker compose exec router ip link set dev eth0 mtu 1500
docker compose exec router ip link set dev eth1 mtu 1500
docker compose exec router ip route replace 172.28.41.0/24 dev eth0 mtu 1400
docker compose exec router ip route replace 172.28.42.0/24 dev eth1 mtu 1400

# Bật Firewall chặn gói ICMP do Router sinh ra (chặn thông báo Frag Needed)
docker compose exec router iptables -F OUTPUT
docker compose exec router iptables -F FORWARD
docker compose exec router iptables -I OUTPUT -p icmp -j DROP

# Reset route cache trên Client & Server để bắt đầu phiên mới từ đầu (MSS mặc định 1460)
docker compose exec client ip route del 172.28.42.0/24 2>/dev/null || true
docker compose exec client ip route add 172.28.42.0/24 via 172.28.41.254
docker compose exec web-server ip route del 172.28.41.0/24 2>/dev/null || true
docker compose exec web-server ip route add 172.28.41.0/24 via 172.28.42.254

echo "✅ Đã kích hoạt lỗi Path MTU Blackhole!"
echo "👉 Hiện tượng:"
echo "   1. Ping 64B: 0% packet loss (mượt mà)."
echo "   2. Ping 1450B (-M do): Request timed out 100% (không có ICMP Frag Needed báo về)."
echo "   3. Web (curl): Bắt tay TCP OK, HTTP 200 OK, nhưng tải về 0 bytes (treo vô tận)."
