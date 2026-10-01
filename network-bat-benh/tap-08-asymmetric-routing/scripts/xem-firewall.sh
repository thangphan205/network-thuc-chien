#!/usr/bin/env bash
# GOC NHIN HAI FIREWALL — mo o terminal thu 2 (khong can `watch`).
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
NHIP=${1:-2}
while true; do
    clear 2>/dev/null || true
    echo "=============================================================="
    echo " HAI FIREWALL                                  $(date -u '+%H:%M:%S') UTC"
    echo "=============================================================="
    echo " server đang về LAN client qua : $(server_dang_ve)   (.251=fw-a  .252=fw-b)"
    for F in $FWA $FWB; do
        echo ""
        echo " [$F]  session port 80: $(so_conntrack_80 $F)   gói INVALID đã DROP: $(so_invalid $F)   tcp_loose=$(docker exec $F sysctl -n net.netfilter.nf_conntrack_tcp_loose 2>/dev/null)"
        docker exec $F sh -c "conntrack -L -p tcp --dport 80 2>/dev/null" | sed 's/^/     /'
    done
    echo ""; echo " (làm mới mỗi ${NHIP}s — Ctrl+C để dừng)"
    sleep "$NHIP"
done
