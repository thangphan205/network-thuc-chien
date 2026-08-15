#!/usr/bin/env bash
# Script test kiểm tra bảng ARP và Ping từ Client
echo "=========================================="
echo "🩺 [BƯỚC 1] Soi địa chỉ MAC THỰC TẾ của Server (172.28.5.10):"
echo "=========================================="
docker compose exec server ip link show eth0 | grep ether

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Soi bảng ARP (ip neigh) trên Client:"
echo "=========================================="
docker compose exec client ip neigh show

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Thử Ping từ Client sang Server:"
echo "=========================================="
docker compose exec client ping -c 3 172.28.5.10
