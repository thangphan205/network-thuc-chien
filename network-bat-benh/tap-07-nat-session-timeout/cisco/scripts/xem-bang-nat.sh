#!/usr/bin/env bash
# GOC NHIN PHIA R1 — mo o terminal thu 2, chay suot buoi demo.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

NHIP=${1:-3}
while true; do
    THONG_KE=$(thong_ke)
    MAY=$(ban_dich_theo_may)
    clear 2>/dev/null || true
    echo "=============================================================="
    echo " GÓC NHÌN PHÍA R1 (show ip nat statistics)      $(date -u '+%H:%M:%S') UTC"
    echo "=============================================================="
    echo "$THONG_KE"
    echo ""
    echo " Ai đang chiếm bảng:"
    echo "$MAY"
    echo ""
    echo " (mỗi lần đọc R1 mất vài giây, nghỉ thêm ${NHIP}s rồi đọc lại — Ctrl+C để dừng)"
    sleep "$NHIP"
done
