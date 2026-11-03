#!/usr/bin/env bash
# ==============================================================================
# KB2 — ⭐ NAT xoa phien TCP, im lang tuyet doi (trung tam ca tap)
#
# established timeout ep xuong 10s, tcp_loose=0 (mac dinh Linux la 1, xem README). Idle 12s vuot
# nguong -> gateway XOA entry khoi conntrack. Goi GET #2 den, khong khop entry
# nao -> bi coi la INVALID -> DROP. Khong RST, khong ICMP, khong gi ca.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

buoc "KB2 — NAT established timeout = 10s, tcp_loose=0"
dat_tcp_timeout 10
dat_loose 0
xac_nhan_sysctl net.netfilter.nf_conntrack_tcp_timeout_established 10

echo "  Mở 1 kết nối -> GET #1 -> idle 12s (vượt 10s) -> GET #2 trên CHÍNH kết nối đó:"
T0=$(date +%s)
N=$(hai_get_qua_idle 12)
T1=$(date +%s)
echo "  👉 Số phản hồi HTTP 200 nhận được: ${N}/2   (mất $((T1-T0))s — client CHỜ HẾT TIMEOUT riêng của nó)"
echo ""
echo "  Phiên trong bảng conntrack của gateway SAU khi GET #2 thất bại:"
xem_conntrack_80 | sed 's/^/     /'
echo ""
echo "👉 Đọc chữ ký:"
echo "   • GET #2 không nhận được gì — không RST, không ICMP. Client tự bỏ cuộc"
echo "     sau khi HẾT TIMEOUT CỦA CHÍNH NÓ (không phải của NAT)."
echo "   • Cả hai đầu (client + server) vẫn tin kết nối còn sống — chỉ gateway"
echo "     ở giữa biết nó đã xóa entry."
echo "   • Lab đặt tcp_loose=0 để giống firewall chặt. Linux mặc định là 1 và ca này ra 2/2."
