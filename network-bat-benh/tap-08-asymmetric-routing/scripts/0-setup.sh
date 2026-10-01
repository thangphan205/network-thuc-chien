#!/usr/bin/env bash
# 0-setup.sh — dua lab ve trang thai KHOE (duong ve doi xung), idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🔧 [1/5] Khởi động toàn bộ lab..."
docker compose up -d --build >/dev/null 2>&1
echo "🔧 [2/5] Đặt lại route tĩnh (client đi qua fw-a; server về qua fw-a)..."
dat_route_client
server_ve a
echo "🔧 [3/5] Dựng lại luật stateful trên CẢ HAI firewall..."
luat_stateful $FWA; luat_stateful $FWB
dat_loose $FWA 0; dat_loose $FWB 0
xoa_conntrack $FWA; xoa_conntrack $FWB
docker exec $FWA iptables -Z FORWARD >/dev/null 2>&1; docker exec $FWB iptables -Z FORWARD >/dev/null 2>&1
echo "🔧 [4/5] Chờ nginx sẵn sàng..."
cho_san_sang
echo "🔧 [5/5] Kiểm tra trạng thái khỏe..."
C=$(curl_thu); P=$(ping_thu)
if [ "$C" != "200" ] || [ "$P" != "THONG" ]; then
    echo "❌ LỖI: trạng thái khỏe mà ping=$P curl=$C. Kiểm tra lại lab." >&2; exit 1
fi
echo ""
echo "✅ Trạng thái bình thường đã sẵn sàng."
echo "   ping  -> $P"
echo "   curl  -> HTTP $C   (SYN và SYN-ACK cùng đi qua fw-a: server về qua $(server_dang_ve))"
echo ""
echo "👉 Terminal 2 — góc nhìn hai firewall:  ./scripts/xem-firewall.sh"
