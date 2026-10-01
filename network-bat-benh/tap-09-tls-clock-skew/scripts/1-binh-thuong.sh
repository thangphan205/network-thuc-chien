#!/usr/bin/env bash
# ==============================================================================
# KB1 — TRANG THAI KHOE.  Chu ky: verify 0, curl 200, lech gio ~0.
#
# Chay truoc tien de co MOC SO SANH. Khong co moc nay thi moi con so o cac kich
# ban sau deu vo nghia: ban khong biet 20 ms la nhanh hay cham, khong biet
# "notAfter 2028" la binh thuong hay bat thuong.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "✅ KB1 — đặt cert HỢP LỆ (server.crt), đồng hồ client đúng giờ..."
dat_cert good
GIO_GIA=""

buoc "CHỮ KÝ: KHỎE"
in_chu_ky
echo ""
echo "👉 Đọc chữ ký:"
echo "   • LỆCH GIỜ ~0 giây  -> hai đồng hồ khớp. Mọi kết luận về thời hạn cert"
echo "     từ đây trở đi đều đáng tin."
echo "   • openssl verify 0 (ok) VÀ curl 200 — cả hai góc nhìn cùng đồng ý."
echo "     Nhớ kỹ: hai góc nhìn này CÓ THỂ mâu thuẫn nhau (xem MR2)."
echo "   • Ghi lại notBefore/notAfter ở trên. Các kịch bản sau sẽ đổi cert, và"
echo "     việc ĐẦU TIÊN bạn làm khi debug là so cặp số này với đồng hồ."
