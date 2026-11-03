#!/usr/bin/env bash
# don-dep.sh — xoa lab Cisco (container, network, thu muc clab). Giu lai image.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

clab destroy -t nat.clab.yml --cleanup >/dev/null 2>&1
echo "✅ Đã xoá lab Cisco. Image vẫn giữ lại để lần sau không phải build."
