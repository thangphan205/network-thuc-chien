#!/usr/bin/env bash
# ==============================================================================
# DESTROY CONTAINERLAB LAB
# Usage: ./scripts/destroy.sh [topology.clab.yml | topology-linux.clab.yml]
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib-common.sh

TOPO=${1:-"topology.clab.yml"}

echo "🧹 Đang dọn dẹp Containerlab: $TOPO..."
sudo containerlab destroy -t "$TOPO" --cleanup

echo "🧹 Xoá Linux bridge '$BRIDGE'..."
sudo ip link del "$BRIDGE" 2>/dev/null || true

echo "✅ Đã dọn dẹp sạch sẽ toàn bộ container và bridge mạng."
