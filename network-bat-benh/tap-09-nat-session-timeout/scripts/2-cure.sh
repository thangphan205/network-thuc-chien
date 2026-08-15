#!/usr/bin/env bash
# Chữa bệnh: Khôi phục timeout chuẩn và bật TCP Keepalive
echo "🩺 Đang chữa bệnh: Khôi phục TCP timeout và khuyến nghị bật TCP Keepalive..."
docker compose exec server sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=432000 2>/dev/null || true
echo "✅ Đã khôi phục timeout bình thường (5 ngày)!"
echo "👉 Hiện tượng: Kết nối nhàn rỗi lâu dài không bị đứt đoạn."
