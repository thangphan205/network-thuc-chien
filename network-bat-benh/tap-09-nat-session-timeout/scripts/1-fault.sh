#!/usr/bin/env bash
# Kích hoạt lỗi: Server đóng vai NAT Gateway / Stateful Firewall có Idle Timeout cực ngắn (5 giây)
set -e
echo "🚨 Đang kích hoạt lỗi: Stateful Firewall với TCP Established Timeout = 5s..."

docker compose exec server sh -c '
  # Dựng stateful firewall: chỉ packet thuộc session hợp lệ trong bảng conntrack mới được qua
  iptables -F INPUT
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
  iptables -A INPUT -p tcp --dport 80 -j DROP

  # Session idle quá 5 giây sẽ bị xóa khỏi bảng conntrack (ngoài đời: 350s - vài phút)
  sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=5
  # Tắt mid-stream pickup: packet của session đã bị xóa sẽ bị coi là INVALID (đúng hành vi firewall thật)
  sysctl -w net.netfilter.nf_conntrack_tcp_loose=0
'

# Xác nhận sysctl đã ăn thật — không nuốt lỗi
GOT=$(docker compose exec server sysctl -n net.netfilter.nf_conntrack_tcp_timeout_established | tr -d '\r')
if [ "$GOT" != "5" ]; then
  echo "❌ LỖI: sysctl không ghi được (giá trị hiện tại: ${GOT:-rỗng}). Kiểm tra 'privileged: true' trong docker-compose.yml rồi 'docker compose up -d --force-recreate'." >&2
  exit 1
fi

echo "✅ Đã kích hoạt lỗi Idle Session Timeout (5s)!"
echo "👉 Hiện tượng: Kết nối TCP giữ yên (idle) quá 5 giây sẽ bị Firewall/NAT âm thầm xóa phiên; packet kế tiếp bị DROP im lặng."
