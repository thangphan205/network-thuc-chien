#!/usr/bin/env bash
# GOC NHIN PHIA GATEWAY — mo o terminal thu 3, chay suot buoi hoc.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

NHIP=${1:-2}
echo "🖥️  GÓC NHÌN PHÍA GATEWAY — Ctrl+C để dừng"

while true; do
    clear 2>/dev/null || true
    echo "=============================================================="
    echo " GÓC NHÌN PHÍA GATEWAY ($GATEWAY)             $(date -u '+%H:%M:%S') UTC"
    echo "=============================================================="
    echo ""
    echo " nf_conntrack_tcp_timeout_established = $(doc_tcp_timeout)s"
    echo " nf_conntrack_tcp_loose               = $(doc_loose)"
    echo " nf_conntrack_count (tổng số session)  = $(docker exec $GATEWAY sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null)"
    echo " nf_conntrack_max                     = $(docker exec $GATEWAY sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)"
    echo ""
    echo " ------------------------------------------------------------"
    echo " Bảng conntrack — các phiên port 80/tcp:"
    xem_conntrack_80 | sed 's/^/   /'
    echo ""
    echo " (làm mới mỗi ${NHIP}s — Ctrl+C để dừng)"
    sleep "$NHIP"
done
