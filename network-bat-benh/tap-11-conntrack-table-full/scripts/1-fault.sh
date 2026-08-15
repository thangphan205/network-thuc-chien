#!/usr/bin/env bash
# Kích hoạt lỗi: Hạ giới hạn conntrack_max xuống mức tối thiểu (10 entries)
echo "🚨 Đang kích hoạt lỗi: Giảm net.netfilter.nf_conntrack_max = 10..."
docker compose exec server sysctl -w net.netfilter.nf_conntrack_max=10 2>/dev/null || true
echo "✅ Đã hạ conntrack_max xuống 10!"
echo "👉 Hiện tượng: Khi có nhiều kết nối đồng thời, bảng conntrack bị tràn, server sẽ drop ngẫu nhiên các kết nối mới (Table Full, Dropping Packet)."
