#!/usr/bin/env bash
# Chữa bệnh: Khôi phục timeout chuẩn (5 ngày) và khuyến nghị bật TCP Keepalive
set -e
echo "🩺 Đang khắc phục sự cố (Fixing): Khôi phục TCP timeout về giá trị mặc định..."

docker compose exec server sh -c '
  sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=432000
  sysctl -w net.netfilter.nf_conntrack_tcp_loose=1
'

GOT=$(docker compose exec server sysctl -n net.netfilter.nf_conntrack_tcp_timeout_established | tr -d '\r')
if [ "$GOT" != "432000" ]; then
  echo "❌ LỖI: sysctl không ghi được (giá trị hiện tại: ${GOT:-rỗng}). Kiểm tra 'privileged: true' trong docker-compose.yml." >&2
  exit 1
fi

echo "✅ Đã khôi phục timeout bình thường (5 ngày)!"
echo "👉 Ngoài đời không chỉnh được thiết bị NAT của nhà mạng/cloud — thuốc đúng là bật TCP Keepalive phía ứng dụng (xem mục Đúc Kết trong README)."
