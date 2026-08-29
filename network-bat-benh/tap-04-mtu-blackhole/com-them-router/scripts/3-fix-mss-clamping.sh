#!/usr/bin/env bash
# Kịch bản 3: Sửa lỗi chuẩn Enterprise bằng TCP MSS Clamping trên Router (Chain FORWARD)
set -e
echo "🩺 [KỊCH BẢN 3] Áp dụng TCP MSS Clamping trên Router (FORWARD chain)..."

# Giữ nguyên luật chặn ICMP và MTU 1400 trên router
# Bật TCP MSS Clamping trên chain FORWARD: tự động sửa trường MSS trong gói TCP SYN/SYN-ACK đi ngang qua
docker compose exec router iptables -t mangle -F
docker compose exec router iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Reset route cache trên Client & Server
docker compose exec client ip route del 172.28.42.0/24 2>/dev/null || true
docker compose exec client ip route add 172.28.42.0/24 via 172.28.41.254
docker compose exec web-server ip route del 172.28.41.0/24 2>/dev/null || true
docker compose exec web-server ip route add 172.28.41.0/24 via 172.28.42.254

echo "✅ Đã bật TCP MSS Clamping trên Router!"
echo "👉 Cơ chế: Router tự động rewrite MSS trong TCP SYN header thành 1360 bytes (1400 - 40 bytes IP/TCP header)."
echo "👉 Hai đầu Client và Server đồng thuận truyền segment tối đa 1360 bytes -> Không có gói nào vượt 1400 -> Web tải mượt mà!"
