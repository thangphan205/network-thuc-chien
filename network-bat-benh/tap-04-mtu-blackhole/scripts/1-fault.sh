#!/usr/bin/env bash
# Kích hoạt lỗi: Mô phỏng Path MTU Blackhole (Gói tin lớn bị Drop âm thầm)
#
# Luật DROP đặt ở chain INPUT của CLIENT (không phải OUTPUT của server) để mô phỏng
# đúng "router giữa đường vứt gói chiều Server -> Client". Quan trọng: đặt ở phía
# client thì tcpdump/Wireshark vẫn bắt được các gói [TCP Retransmission] TRƯỚC khi
# chúng bị netfilter vứt. Nếu đặt ở OUTPUT của server, gói bị vứt trước cả packet tap
# => không phía nào bắt được gói nào, mất luôn bằng chứng để dạy.
set -e
echo "🚨 Đang kích hoạt lỗi: Path MTU Blackhole (Chặn gói > 1000 bytes chiều Server → Client)..."

# Reset sạch trạng thái của lần demo trước (kể cả route MTU do 2-fix.sh đặt)
docker compose exec web-server iptables -F
docker compose exec web-server ip route del 172.28.4.20/32 dev eth0 2>/dev/null || true
docker compose exec client iptables -F

# Tắt offload để Wireshark thấy đúng kích thước segment thật (1448B), không bị gộp gói ảo.
# GSO/TSO ở server là thủ phạm chính: nếu bật, kernel đẩy nguyên khối 3093 bytes qua veth
# và Wireshark hiển thị một gói "length 3093" không hề tồn tại trên dây thật.
docker compose exec web-server ethtool -K eth0 tso off gso off >/dev/null 2>&1 || true
docker compose exec client ethtool -K eth0 gro off >/dev/null 2>&1 || true

docker compose exec client iptables -I INPUT -p tcp --sport 80 -m length --length 1000:65535 -j DROP
docker compose exec client iptables -I INPUT -p icmp -m length --length 1000:65535 -j DROP
echo "✅ Đã kích hoạt lỗi MTU Blackhole!"
echo "👉 Hiện tượng: Ping 64B mượt, bắt tay TCP xong, header HTTP 200 về được — nhưng body trang web không bao giờ tới."
