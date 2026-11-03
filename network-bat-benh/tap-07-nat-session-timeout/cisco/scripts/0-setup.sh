#!/usr/bin/env bash
# 0-setup.sh — dung lai lab Cisco tu dau, idempotent. Chay lai truoc moi lan demo:
# bo dem "missed" khong reset khi clear translation, deploy lai la cach sach nhat.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

if ! docker image inspect vrnetlab/cisco_iol:17.12.01 >/dev/null 2>&1; then
    echo "❌ LỖI: chưa có image vrnetlab/cisco_iol:17.12.01. Xem hướng dẫn build trong README." >&2
    exit 1
fi

echo "🔧 [1/3] Deploy lab (xoá lab cũ nếu có)..."
clab deploy -t nat.clab.yml --reconfigure >/dev/null 2>&1

echo "🔧 [2/3] Chờ R1 khởi động..."
cho_r1_san_sang

echo "🔧 [3/3] Kiểm tra trạng thái khỏe..."
HTTP=$(curl_moi "$NHAN_VIEN")
if [ "$HTTP" != "200" ]; then
    echo "❌ LỖI: nhan-vien gọi server ra ${HTTP:-rỗng} (mong đợi 200). Kiểm tra lại lab." >&2
    exit 1
fi

echo ""
echo "✅ Trạng thái bình thường đã sẵn sàng. nhan-vien gọi server: HTTP $HTTP"
thong_ke | sed 's/^/   /'
echo ""
echo "👉 Mở terminal thứ 2 — góc nhìn bảng NAT của R1:"
echo "   ./scripts/xem-bang-nat.sh"
