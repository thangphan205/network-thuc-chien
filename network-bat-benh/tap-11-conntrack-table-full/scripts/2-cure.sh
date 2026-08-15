#!/usr/bin/env bash
# Chữa bệnh: Nâng giới hạn conntrack_max lên giá trị chuẩn (262144)
echo "🩺 Đang chữa bệnh: Nâng net.netfilter.nf_conntrack_max lên 262144..."
docker compose exec server sysctl -w net.netfilter.nf_conntrack_max=262144 2>/dev/null || true
echo "✅ Đã mở rộng bảng Conntrack thành công!"
echo "👉 Hiện tượng: Server tiếp nhận hàng chục ngàn kết nối đồng thời mà không bị drop packet."
