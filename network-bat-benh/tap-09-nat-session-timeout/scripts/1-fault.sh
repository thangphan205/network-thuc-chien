#!/usr/bin/env bash
# Kích hoạt lỗi: Hạ TCP Idle Timeout trên Conntrack xuống cực ngắn (5 giây)
echo "🚨 Đang kích hoạt lỗi: Giảm TCP Established Timeout trên Conntrack xuống 5s..."
docker compose exec server sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=5 2>/dev/null || true
echo "✅ Đã kích hoạt lỗi Idle Session Timeout!"
echo "👉 Hiện tượng: Kết nối TCP giữ yên (idle) quá 5 giây sẽ bị Firewall/NAT âm thầm xóa phiên; khi gửi data tiếp theo sẽ bị drop hoặc reset."
