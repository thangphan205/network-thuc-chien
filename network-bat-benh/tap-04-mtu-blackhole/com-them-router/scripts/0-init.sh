#!/usr/bin/env bash
# Khởi tạo định tuyến (Routing) và tắt Offload để Wireshark bắt gói chuẩn
set -e
echo "🔧 Đang khởi tạo bảng định tuyến cho Client, Server và Router..."

# 1. Định tuyến Client -> Server qua Router (172.28.41.254)
docker compose exec client ip route replace 172.28.42.0/24 via 172.28.41.254

# 2. Định tuyến Server -> Client qua Router (172.28.42.254)
docker compose exec web-server ip route replace 172.28.41.0/24 via 172.28.42.254

# 3. Tắt TCP offload để thấy đúng kích thước gói tin trên dây
docker compose exec client ethtool -K eth0 gro off tso off gso off >/dev/null 2>&1 || true
docker compose exec web-server ethtool -K eth0 gro off tso off gso off >/dev/null 2>&1 || true
docker compose exec router ethtool -K eth0 gro off tso off gso off >/dev/null 2>&1 || true
docker compose exec router ethtool -K eth1 gro off tso off gso off >/dev/null 2>&1 || true

# 4. Router đã tự bật IP Forwarding qua docker-compose sysctls


echo "✅ Đã định tuyến thành công!"
echo "👉 Client (172.28.41.20) <---> [Router: 172.28.41.254 | 172.28.42.254] <---> Web Server (172.28.42.10)"
