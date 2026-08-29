#!/usr/bin/env bash
# Kịch bản 4: Sửa lỗi bằng cách Mở lại ICMP trên Router Firewall
set -e
echo "🩺 [KỊCH BẢN 4] Gỡ bỏ luật chặn ICMP trên Router Firewall để PMTUD hoạt động tự nhiên..."

docker compose exec router iptables -F OUTPUT
docker compose exec router iptables -F FORWARD
docker compose exec router iptables -t mangle -F

# Reset route cache trên Client & Server
docker compose exec client ip route del 172.28.42.0/24 2>/dev/null || true
docker compose exec client ip route add 172.28.42.0/24 via 172.28.41.254
docker compose exec web-server ip route del 172.28.41.0/24 2>/dev/null || true
docker compose exec web-server ip route add 172.28.41.0/24 via 172.28.42.254

echo "✅ Đã gỡ bỏ luật chặn ICMP trên Router!"
echo "👉 Router đã có thể gửi thông báo 'Frag Needed' khi gặp gói lớn -> PMTUD hoạt động bình thường."
