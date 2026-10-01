#!/usr/bin/env bash
# ==============================================================================
# KB1 — TRANG THAI KHOE. Moc so sanh cho tat ca nhung gi den sau.
# Truoc khi hoc doc benh, phai biet nguoi khoe thi cac chi so ra bao nhieu.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "✅ KB1 — trạng thái bình thường (không kích hoạt lỗi nào)."
xoa_log_dns
buoc "CHU KỲ CỦA NGƯỜI KHỎE"
in_chu_ky
echo ""
echo "👉 Ghi nhớ 3 con số này, mỗi ca bệnh sau sẽ làm lệch đúng một trong số chúng:"
echo "   • dig trả lời trong ~1 ms       -> server SỐNG và trả lời NGAY."
echo "   • IP theo dig == IP theo NSS    -> không ai chen ngang giữa DNS và ứng dụng."
echo "   • trang nhận được = SERVER MỚI  -> đúng địa chỉ, đúng máy."
