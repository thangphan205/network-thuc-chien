#!/usr/bin/env bash
# ==============================================================================
# CHỮA BỆNH: NODE-B PHÁT GRATUITOUS ARP
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib-common.sh

S2_CTR=$(clab_ctr node-b)

if [ -z "$S2_CTR" ]; then
    echo "❌ Không tìm thấy container node-b. Hãy chạy ./scripts/deploy.sh trước."
    exit 1
fi

echo "🩺 Server 2 phát 3 gói Unsolicited Gratuitous ARP ra toàn bộ Server LAN ($BRIDGE)..."
docker exec "$S2_CTR" arping -U -c 5 -I eth1 "$VIP"

echo ""
echo "✅ Đã phát GARP xong!"
echo "👉 Chạy ./scripts/test.sh để thấy Client thông mạng ngay lập tức."
