#!/usr/bin/env bash
# Kích hoạt lỗi: Mô phỏng Stateful Firewall Drop do Asymmetric Routing
set -e
echo "🚨 Đang kích hoạt lỗi: Stateful Firewall chặn gói tin do đường về lệch tuyến (Asymmetric)..."
docker compose exec server iptables -F
docker compose exec server iptables -I OUTPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -j DROP

# Xác nhận rule đã áp — fail loud nếu server thiếu iptables/quyền
if ! docker compose exec server iptables -C OUTPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -j DROP 2>/dev/null; then
  echo "❌ Không áp được rule iptables trên server. Kiểm tra server có iptables + cap_add NET_ADMIN." >&2
  exit 1
fi

echo "✅ Đã kích hoạt lỗi Asymmetric Routing!"
echo "👉 Hiện tượng: Ping thông suốt 2 chiều, nhưng TCP kết nối bị đứt ngay tại bước bắt tay vì gói SYN-ACK chiều về bị chặn."
