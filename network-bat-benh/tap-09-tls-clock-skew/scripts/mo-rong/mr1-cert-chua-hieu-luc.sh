#!/usr/bin/env bash
# ==============================================================================
# MR1 — CERT CHUA DEN NGAY HIEU LUC.  Chu ky: verify 9, LECH GIO ~0.
#
# Tinh huong ngoai doi (it gap hon KB2 nhung kho doan hon nhieu):
#   - May chu noi bo cap cert bi lech gio VE TUONG LAI luc ky -> notBefore o
#     tuong lai, ca ha tang tu choi mot cert vua moi cap xong.
#   - CA noi bo cai dat sai mui gio, cert "co hieu luc tu 7 tieng nua".
#   - Cluster vua doi sang cert moi som hon lich cat-over.
#
# Vi sao phai co kich ban nay? Vi no la CAI GUONG cua KB3-qua-khu: cung ra ma 9.
# Mot ben la cert sai, mot ben la dong ho sai. Cung mot thong bao loi.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR1 — cho nginx serve notyet.crt (notBefore = 01/01/2035)..."
dat_cert notyet
GIO_GIA=""

buoc "CHỮ KÝ: CERT CHƯA HIỆU LỰC (thủ phạm ở SERVER/CA)"
in_chu_ky
echo ""
echo "👉 Đọc chữ ký:"
echo "   • verify 9 'certificate is not yet valid' + LỆCH GIỜ ~0"
echo "     -> hai đồng hồ khớp, nên notBefore là SỰ THẬT. Cert cấp sai ngày."
echo "   • Thông báo này làm nhiều người bỏ qua vì nó nghe vô lý ('cert mới cấp"
echo "     mà báo chưa hiệu lực?'). Nó hoàn toàn có thật, và nguyên nhân gần như"
echo "     luôn là máy KÝ cert bị lệch giờ về tương lai."
echo ""
echo "   ⚠️ So sánh với KB3 lần chạy '2020': cùng ra mã 9, nhưng khi đó LỆCH GIỜ"
echo "      là -6 năm. Ở đây lệch ~0. Luôn đọc HAI chỉ số cùng lúc, đừng đọc một."
