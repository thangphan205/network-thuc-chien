#!/usr/bin/env bash
# ==============================================================================
# KB1 — TRANG THAI KHOE. Moc so sanh cho tat ca nhung gi den sau.
# Truoc khi hoc doc benh, phai biet nguoi khoe thi cac chi so ra bao nhieu.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "✅ KB1 — trang thai binh thuong (khong kich hoat loi nao)."
xoa_log_dns
buoc "CHU KY CUA NGUOI KHOE"
in_chu_ky
echo ""
echo "👉 Ghi nho 3 con so nay, moi ca benh sau se lam lech dung mot trong so chung:"
echo "   • dig tra loi trong ~1 ms       -> server SONG va tra loi NGAY."
echo "   • IP theo dig == IP theo NSS    -> khong ai chen ngang giua DNS va ung dung."
echo "   • trang nhan duoc = SERVER MOI  -> dung dia chi, dung may."
