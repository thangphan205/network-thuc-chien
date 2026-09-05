#!/usr/bin/env bash
# ==============================================================================
# DEPLOY CONTAINERLAB LAB
# Usage: ./scripts/deploy.sh [topology.clab.yml | topology-linux.clab.yml]
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib-common.sh

TOPO=${1:-"topology.clab.yml"}

echo "🚀 [1/4] Kiểm tra và build Docker image 'tap05-ha-node:latest'..."
if ! docker image inspect tap05-ha-node:latest >/dev/null 2>&1; then
    docker build -t tap05-ha-node:latest .
else
    echo "✅ Image 'tap05-ha-node:latest' đã có sẵn."
fi

echo "🚀 [2/4] Chuẩn bị Linux bridge '$BRIDGE' (Server LAN)..."
ensure_bridge

echo "🚀 [3/4] Deploy topology bằng Containerlab: $TOPO..."
sudo containerlab deploy -t "$TOPO"

echo "🚀 [4/4] Kiểm tra 3 veth đã gắn đúng vào bridge '$BRIDGE'..."
# Containerlab thỉnh thoảng gắn thiếu veth vào bridge. Thiếu 1 link là đứt L2,
# hai server không thấy VRRP của nhau và cùng lên MASTER (split-brain).
for IF in srv-rtr srv-na srv-nb; do
    MASTER=$(ip -o link show "$IF" 2>/dev/null | grep -o "master [^ ]*" | awk '{print $2}')
    if [ "$MASTER" != "$BRIDGE" ]; then
        echo "  ⚠️  $IF chưa gắn vào $BRIDGE — đang gắn lại..."
        sudo ip link set "$IF" master "$BRIDGE"
        sudo ip link set "$IF" up
    fi
done
ip -br link show master "$BRIDGE" | awk '{printf "  ✅ %-10s %s\n", $1, $2}'

echo ""
echo "✅ Lab đã khởi động thành công!"
echo "👉 Chờ ~5s cho VRRP hội tụ, rồi chạy ./scripts/test.sh để kiểm tra trạng thái ban đầu."
