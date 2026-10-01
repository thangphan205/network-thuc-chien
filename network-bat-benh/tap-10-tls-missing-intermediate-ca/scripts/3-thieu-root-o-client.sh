#!/usr/bin/env bash
# ==============================================================================
# KB3 — ⭐⭐ CLIENT THIEU ROOT.  Chu ky: num=20, DEPTH=1.
#
# ĐÂY LA CA BENH TRUNG TAM CUA CA TAP.
#
# Kich ban nay KHONG DUNG MOT NGON TAY nao vao server. nginx van gui dung chuoi
# day du 2 tang cua KB1. Thu duy nhat thay doi: go root CA cua lab khoi trust
# store cua may client.
#
# Va ket qua in ra la:
#         verify error:num=20:unable to get local issuer certificate
#
# ...tuc la DUNG TUNG CHU cai ma KB2 in ra. Cung ma so. Cung dong chu. Cung
# thong bao cua curl. Hai ca benh trai nguoc nhau hoan toan:
#
#         KB2:  server gui thieu   ->  sua CAU HINH SERVER
#         KB3:  client thieu root  ->  sua TRUST STORE CLIENT
#
# Thu duy nhat tach duoc chung la con so DEPTH:
#         depth=0  ->  cert hong la LEAF        ->  server chua gui du
#         depth=1  ->  cert hong la INTERMEDIATE ->  client khong tin nguoi ky
#
# ⚠️ Day la ly do khong duoc chan doan bang `curl` mot minh. curl in dong chu,
#    khong in depth. Phai go `openssl s_client` va DOC DONG depth= ngay TRUOC
#    dong verify error.
#
# Tinh huong ngoai doi: image container base (alpine, distroless, scratch) khong
# co CA noi bo cua cong ty; JVM co truststore RIENG (`cacerts`) ma khong ai nho
# cap nhat khi doi CA; may dev moi cai lai; thiet bi IoT khong duoc cap nhat CA
# bundle trong nhieu nam.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB3 — server GIỮ NGUYÊN chuỗi đầy đủ. Chỉ gỡ root khỏi trust store client..."
dat_chuoi good        # y het KB1
go_root               # ...va day la thay doi DUY NHAT

buoc "CHỮ KÝ: CLIENT KHÔNG TIN NGƯỜI KÝ"
in_chu_ky
echo ""
echo "👉 Đọc chữ ký:"
echo "   • Số cert trên dây vẫn là 2 — server gửi ĐỦ. So sánh với KB2 (1 cert)."
echo "   • num=20, dòng chữ y HỆT KB2. Nếu chỉ đọc dòng chữ, bạn sẽ đi sửa"
echo "     cấu hình nginx — và nginx đang hoàn toàn đúng."
echo "   • DEPTH=1. Cert hỏng là INTERMEDIATE, ở tầng TRÊN. Server đã làm xong"
echo "     phần việc của nó; phần còn thiếu nằm trên máy này."
echo '   • Chữa: cài root CA vào trust store. ./scripts/0-setup.sh làm việc đó.'
echo ""
echo "   🧠 HỌC THUỘC ĐÚNG BẢNG NÀY LÀ XONG TẬP 10:"
echo "        num=20  DEPTH=0  ->  SERVER gửi thiếu intermediate  ->  sửa fullchain"
echo "        num=20  DEPTH=1  ->  CLIENT thiếu root trong store  ->  cài CA"
echo ""
echo "   👉 Chạy liên tiếp để thấy tận mắt:  ./scripts/2-thieu-intermediate.sh"
echo "      rồi ./scripts/3-thieu-root-o-client.sh. Chỉ một con số khác nhau."
