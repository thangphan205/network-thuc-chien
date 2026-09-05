#!/usr/bin/env bash
# ==============================================================================
# KÍCH HOẠT LỖI: FAILOVER KHÔNG GỬI GARP
#
# Mục tiêu: dựng lại đúng ca bệnh ngoài đời — script HA tự chế cướp VIP nhưng
# QUÊN phát Gratuitous ARP, khiến router giữ MAC của node đã chết.
#
# THỨ TỰ VÀ TÍN HIỆU DƯỚI ĐÂY LÀ BẮT BUỘC:
#  - Phải hạ keepalived trên NODE-B TRƯỚC. Nếu để nó chạy, nó sẽ tự lên MASTER
#    và TỰ PHÁT GARP -> bệnh tự khỏi trong ~0.5s, không quan sát được gì.
#  - Phải dùng SIGKILL (kill -9) cho server 1. Khi nhận SIGTERM, keepalived tắt
#    "lịch sự": nó phát một VRRP advertisement priority = 0 để nhường quyền.
#    Server 2 thấy priority 0 sẽ lên MASTER NGAY LẬP TỨC (không chờ hết 3 chu kỳ
#    advert) và phát GARP -> hỏng kịch bản lab.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib-common.sh

S1_CTR=$(clab_ctr node-a)
S2_CTR=$(clab_ctr node-b)

if [ -z "$S1_CTR" ] || [ -z "$S2_CTR" ]; then
    echo "❌ Không tìm thấy container node-a/node-b. Hãy chạy ./scripts/deploy.sh trước."
    exit 1
fi

echo "🚨 [1/4] Hạ Keepalived trên Server 2 TRƯỚC (để nó không tự phát GARP)..."
docker exec "$S2_CTR" pkill -9 keepalived 2>/dev/null || true

echo "🚨 [2/4] Server 1 (MASTER) chết đột ngột — SIGKILL, không kịp nhường quyền..."
docker exec "$S1_CTR" pkill -9 keepalived 2>/dev/null || true

echo "🚨 [3/4] Gỡ VIP khỏi Server 1..."
docker exec "$S1_CTR" ip addr del $VIP/24 dev eth1 2>/dev/null || true

echo "🚨 [4/4] Server 2 (BACKUP) cướp VIP thủ công — KHÔNG GỬI GARP..."
# `ip addr replace` chỉ gắn địa chỉ vào interface. Kernel Linux KHÔNG tự phát
# GARP (net.ipv4.conf.*.arp_notify mặc định = 0) -> đúng kịch bản "quên GARP".
docker exec "$S2_CTR" ip addr replace $VIP/24 dev eth1

echo ""
echo "✅ Đã mô phỏng xong failover không GARP."
echo "👉 Chạy ./scripts/test.sh để thấy hiện tượng Blackhole (Server 2 đã cầm VIP nhưng Client bị timeout)."
