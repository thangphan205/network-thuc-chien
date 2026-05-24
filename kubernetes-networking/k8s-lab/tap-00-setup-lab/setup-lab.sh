#!/bin/bash

# ==========================================
# Router Script - Setup Lab K8s 3 Nodes
# Tự động nhận diện CPU (ARM vs AMD/Intel) và gọi script tối ưu tương ứng.
# Kênh: Network Thực Chiến (youtube.com/@NetworkThucChien)
# ==========================================

set -e

# Phát hiện kiến trúc CPU của máy host
ARCH=$(uname -m)

echo "🔍 Đang tự động nhận diện kiến trúc CPU của bạn..."
sleep 0.5

if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    echo "🍏 PHÁT HIỆN CHIP ARM (ARM64 / Apple Silicon)!"
    echo "🚀 Đang tự động gọi script tối ưu: ./setup-lab-arm.sh"
    echo "============================================================"
    chmod +x "$(dirname "$0")/setup-lab-arm.sh"
    exec "$(dirname "$0")/setup-lab-arm.sh" "$@"
else
    echo "💻 PHÁT HIỆN CHIP AMD/INTEL (x86_64 / AMD64)!"
    echo "🚀 Đang tự động gọi script tối ưu: ./setup-lab-amd.sh"
    echo "============================================================"
    chmod +x "$(dirname "$0")/setup-lab-amd.sh"
    exec "$(dirname "$0")/setup-lab-amd.sh" "$@"
fi