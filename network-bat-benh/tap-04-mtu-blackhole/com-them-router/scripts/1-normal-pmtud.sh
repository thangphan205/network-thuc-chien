#!/usr/bin/env bash
# Kịch bản 1: Đường truyền MTU 1400 tiêu chuẩn (PMTUD hoạt động bình thường, KHÔNG bị Blackhole)
set -e
echo "🔄 [KỊCH BẢN 1] Thiết lập đường truyền MTU 1400 trên Router, cho phép ICMP thông suốt..."

# Reset iptables trên các node
docker compose exec router iptables -F
docker compose exec router iptables -F FORWARD
docker compose exec router iptables -F OUTPUT
docker compose exec router iptables -t mangle -F
docker compose exec client iptables -F
docker compose exec web-server iptables -F

# Đảm bảo card mạng Router nhận gói bình thường (MTU 1500) và áp đặt Route MTU 1400 cho phân đoạn định tuyến
docker compose exec router ip link set dev eth0 mtu 1500
docker compose exec router ip link set dev eth1 mtu 1500
docker compose exec router ip route replace 172.28.41.0/24 dev eth0 mtu 1400
docker compose exec router ip route replace 172.28.42.0/24 dev eth1 mtu 1400

# Reset route cache trên Client & Server
docker compose exec client ip route del 172.28.42.0/24 2>/dev/null || true
docker compose exec client ip route add 172.28.42.0/24 via 172.28.41.254
docker compose exec web-server ip route del 172.28.41.0/24 2>/dev/null || true
docker compose exec web-server ip route add 172.28.41.0/24 via 172.28.42.254

echo "✅ Đã cấu hình MTU=1400 trên Router + Mở ICMP đầy đủ!"
echo "👉 Kỳ vọng: Ping lớn (-M do) sẽ nhận được phản hồi 'Frag needed and DF set (mtu = 1400)' từ Router."
echo "👉 Web tải thành công vì Server nhận được ICMP báo giảm kích thước segment (PMTUD tự điều chỉnh)."
