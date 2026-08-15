#!/usr/bin/env bash
# Kích hoạt lỗi: Mô phỏng Path MTU Blackhole (Gói tin lớn bị Drop âm thầm)
echo "🚨 Đang kích hoạt lỗi: Path MTU Blackhole (Chặn các gói tin > 1000 bytes)..."
docker compose exec web-server iptables -F
docker compose exec web-server iptables -I OUTPUT -p tcp --sport 80 -m length --length 1000:65535 -j DROP
docker compose exec web-server iptables -I OUTPUT -p icmp -m length --length 1000:65535 -j DROP
echo "✅ Đã kích hoạt lỗi MTU Blackhole!"
echo "👉 Hiện tượng: Ping gói nhỏ (64B) chạy mượt, bắt tay TCP SYN/ACK thành công, nhưng tải Web bị đơ đứng im giữa chừng."
