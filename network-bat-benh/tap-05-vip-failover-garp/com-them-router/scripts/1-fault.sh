#!/usr/bin/env bash
# Kích hoạt lỗi: MASTER chết, BACKUP cướp VIP nhưng KHÔNG phát Gratuitous ARP.
# Giống hệt lab chính — chỉ khác: nạn nhân ôm MAC chết lần này là ROUTER.
set -e
cd "$(dirname "$0")/.."
source scripts/_lib.sh

echo "🚨 Đang kích hoạt lỗi: Failover không phát GARP (có router ở giữa)..."
echo "   [1/2] node-a (MASTER) chết..."
docker compose stop node-a >/dev/null 2>&1
echo "   [2/2] node-b (BACKUP) cướp VIP $VIP — KHÔNG gửi GARP..."
docker compose exec node-b ip addr replace $VIP/24 dev eth0

echo "✅ Failover 'thành công'. Bảng ARP của CLIENT vẫn sạch tinh — client hoàn toàn vô can."
echo "👉 Chạy ./scripts/test.sh để xem bệnh đã dời sang đâu."
