#!/usr/bin/env bash
# ==============================================================================
# KB2 — ⭐ NAT xoa phien TCP, im lang tuyet doi (trung tam ca tap)
#
# established timeout ep xuong 5s, tcp_loose=0 (mac dinh kernel). Idle 7s vuot
# nguong -> gateway XOA entry khoi conntrack. Goi GET #2 den, khong khop entry
# nao -> bi coi la INVALID -> DROP. Khong RST, khong ICMP, khong gi ca.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

buoc "KB2 — NAT established timeout = 5s, tcp_loose=0"
dat_tcp_timeout 5
dat_loose 0
dat_nginx dai
xac_nhan_sysctl net.netfilter.nf_conntrack_tcp_timeout_established 5

echo "  Mở 1 kết nối -> GET #1 -> idle 7s (vượt 5s) -> GET #2 trên CHÍNH kết nối đó:"
T0=$(date +%s)
N=$(hai_get_qua_idle 7)
T1=$(date +%s)
echo "  👉 Số phản hồi HTTP 200 nhận được: ${N}/2   (mất $((T1-T0))s — client CHỜ HẾT TIMEOUT riêng của nó)"
echo ""
echo "  Bảng conntrack của gateway SAU khi GET #2 thất bại (không còn entry port 80):"
xem_conntrack_80 | sed 's/^/     /'
echo ""
echo "👉 Đọc chữ ký:"
echo "   • GET #2 không nhận được gì — không RST, không ICMP. Client tự bỏ cuộc"
echo "     sau khi HẾT TIMEOUT CỦA CHÍNH NÓ (không phải của NAT)."
echo "   • Cả hai đầu (client + server) vẫn tin kết nối còn sống — chỉ gateway"
echo "     ở giữa biết nó đã xóa entry."
echo "   • Đối lập với MR3 (server tự đóng FIN): ở đây KHÔNG có gói tin nào cả."
