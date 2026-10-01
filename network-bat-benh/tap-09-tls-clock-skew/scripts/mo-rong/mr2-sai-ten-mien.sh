#!/usr/bin/env bash
# ==============================================================================
# MR2 — CERT SAI TEN MIEN.  Chu ky: openssl bao 0 (ok), curl bao exit 60.
#
# ⚠️ CAI BAY LON NHAT CUA TAP. Day la ca benh duy nhat ma HAI CONG CU CHAN DOAN
#    NOI NGUOC NHAU — va cong cu ma ky thuat vien hay tin nhat lai la cong cu sai.
#
#   `openssl s_client` MAC DINH chi kiem tra 2 thu: chuoi tin cay + thoi han.
#   No KHONG kiem tra ten mien. Cert cap cho other.local, ban hoi secure.local,
#   no van vui ve tra ve "Verify return code: 0 (ok)".
#
#   curl va trinh duyet thi kiem tra ten mien, nen chung tu choi.
#
# Ket qua ngoai doi: ky thuat vien go s_client, thay "ok", ket luan "cert khong
# co van de gi", va di soi nham cho khac trong nhieu gio.
#
# Tinh huong ngoai doi: virtual host moi tro nham vao cert cua site cu; wildcard
# *.example.com dung cho a.b.example.com (wildcard chi phu MOT cap); doi ten
# mien nhung quen cap lai cert; SAN thieu ten "www".
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR2 — cho nginx serve wrongname.crt (còn hạn, CA lab ký, nhưng SAN=$TEN_SAI)..."
dat_cert wrongname
GIO_GIA=""

buoc "CHỮ KÝ: SAI TÊN MIỀN — hỏi '$TEN' (tên mà ứng dụng dùng)"
in_chu_ky "$TEN"

buoc "ĐỐI CHỨNG: hỏi '$TEN_SAI' (đúng tên mà cert được cấp cho)"
in_chu_ky "$TEN_SAI"

buoc "ÉP openssl KIỂM TRA TÊN MIỀN — thêm -verify_hostname"
echo "  openssl s_client ... -verify_hostname $TEN"
echo "    ->  $(verify_openssl "$TEN" "-verify_hostname $TEN")"
echo "  openssl s_client ... (mặc định, KHÔNG có -verify_hostname)"
echo "    ->  $(verify_openssl "$TEN")"
echo ""
echo "👉 Đọc chữ ký:"
echo "   • Lần hỏi '$TEN': openssl 0 (ok) NHƯNG curl exit 60. Hai công cụ"
echo "     mâu thuẫn nhau -> gần như chắc chắn là lỗi TÊN MIỀN, không phải thời hạn."
echo "   • Lần hỏi '$TEN_SAI': cả hai đều OK. Chứng minh cert không hỏng, chỉ là"
echo "     nó được cấp cho một tên khác."
echo "   • Thêm -verify_hostname thì openssl mới nói thật."
echo ""
echo "   🧠 Quy tắc rút ra: KHÔNG BAO GIỜ kết luận 'cert OK' bằng s_client trần."
echo "      Luôn gõ một trong hai:"
echo "          openssl s_client -connect host:443 -servername TEN -verify_hostname TEN"
echo "          curl -v https://TEN/          # curl kiểm tra tên miền sẵn"
echo ""
echo "   • Trình duyệt báo ERR_CERT_COMMON_NAME_INVALID — KHÔNG phải"
echo "     ERR_CERT_DATE_INVALID. Đọc đúng mã lỗi là đi đúng hướng ngay từ đầu."
