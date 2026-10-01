#!/usr/bin/env bash
# ==============================================================================
# KB1 — Trang thai khoe: moc so sanh.
#
# Khong dung gi ca. TCP established timeout van la mac dinh kernel (432000s =
# 5 ngay). Khong co lab nao, khong co gateway nao doi hanh vi nay ca — day la
# hanh vi GOC cua Linux. Ghi lai con so 2/2: moi kich ban sau se lam lech no.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

buoc "KB1 — trạng thái khỏe (chưa đụng gì)"
echo "  nf_conntrack_tcp_timeout_established = $(doc_tcp_timeout)s (mặc định kernel)"
echo ""
echo "  Mở 1 kết nối TCP -> GET #1 -> idle 7s -> GET #2 trên CHÍNH kết nối đó:"
N=$(hai_get_qua_idle 7)
echo "  👉 Số phản hồi HTTP 200 nhận được: ${N}/2"
echo ""
echo "  Session còn nguyên trong conntrack của gateway:"
xem_conntrack_80 | sed 's/^/     /'
