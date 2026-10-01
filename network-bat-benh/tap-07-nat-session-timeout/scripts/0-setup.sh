#!/usr/bin/env bash
# 0-setup.sh — dua lab ve trang thai KHOE, idempotent. Chay lai bat cu luc nao.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🔧 [1/6] Khởi động toàn bộ lab..."
docker compose up -d --build >/dev/null 2>&1

echo "🔧 [2/6] Đặt lại route tĩnh (không sống qua restart)..."
dat_route

echo "🔧 [3/6] Dựng lại luật FORWARD/NAT gốc trên gateway..."
dung_luat_goc

echo "🔧 [4/6] Đặt lại conntrack về giá trị MẶC ĐỊNH của Linux..."
dat_tcp_timeout 432000     # 5 ngay — mac dinh kernel
dat_udp_timeout 30         # 30 giay — mac dinh kernel, NGAN HON TCP RAT NHIEU
dat_loose 0                # mac dinh kernel

echo "🔧 [5/6] Đặt lại nginx trên server về keepalive_timeout mặc định (dài)..."
dat_nginx dai

echo "🔧 [6/6] Kiểm tra trạng thái khỏe..."
cho_server_san_sang
N=$(hai_get_qua_idle 7)
xac_nhan_sysctl net.netfilter.nf_conntrack_tcp_timeout_established 432000
xac_nhan_sysctl net.netfilter.nf_conntrack_tcp_loose 0

if [ "$N" != "2" ]; then
    echo "❌ LỖI: trạng thái khỏe mà vẫn chỉ nhận ${N:-0}/2 phản hồi. Kiểm tra lại lab." >&2
    exit 1
fi

echo ""
echo "✅ Trạng thái bình thường đã sẵn sàng."
echo "   TCP established timeout : 432000s (5 ngay)"
echo "   UDP timeout              : 30s"
echo "   2 GET qua 1 kết nối, idle 7s -> ${N}/2 (đúng như kỳ vọng)"
echo ""
echo "👉 Mở terminal thứ 2 — máy đo phía client:"
echo "   docker exec -it lab07-client sh"
echo "👉 Mở terminal thứ 3 — góc nhìn bảng conntrack của gateway:"
echo "   ./scripts/xem-conntrack.sh"
