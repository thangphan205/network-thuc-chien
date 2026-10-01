#!/usr/bin/env bash
# ==============================================================================
# KB1 — TRANG THAI KHOE.  Chu ky: 2 cert tren day, num=0, HTTP 200.
#
# Moc so sanh. Khong co no thi moi con so o cac kich ban sau deu vo nghia: ban
# khong biet "server gui 1 cert" la binh thuong hay bat thuong.
#
# ⚠️ GHI LAI SO CERT IN RA (2). Ca tap nay xoay quanh dung con so do va con so
#    depth. Chuoi chuan la HAI tang: leaf + intermediate. KHONG kem root — root
#    da nam san trong trust store cua client roi, gui lai la thua.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "✅ KB1 — nginx gửi CHUỖI ĐẦY ĐỦ (leaf + intermediate)..."
cai_root
dat_chuoi good

buoc "CHỮ KÝ: TRẠNG THÁI KHỎE"
in_chu_ky
echo ""
echo "👉 Đọc chữ ký:"
echo "   • 2 cert trên dây. Tầng 0 là leaf, tầng 1 là intermediate ký cho nó."
echo "   • Client lấy tầng 1 nối tiếp lên root ĐÃ CÓ trong trust store -> đủ đường."
echo "   • num=0, không có dòng 'verify error' nào, nên KHÔNG có depth để đọc."
echo ""
echo "   🧠 Nhớ công thức chuỗi chuẩn:"
echo "        fullchain = leaf + intermediate            (server gửi)"
echo "        root                                        (client đã có sẵn)"
echo "      Server gửi phần DƯỚI, client giữ phần TRÊN. Mỗi bên thiếu phần của"
echo "      mình thì hỏng theo một kiểu khác nhau — đó là KB2 và KB3."
