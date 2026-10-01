#!/usr/bin/env bash
# ==============================================================================
# MR3 — CERT TU KY / KHONG TIN DUOC NGUOI KY.  Chu ky: verify 18, LECH GIO ~0.
#
# Tinh huong ngoai doi: dung cert tu ky tren moi truong noi bo; CA noi bo chua
# duoc cai vao trust store cua may/ cua image container; thiet bi middlebox
# (SSL inspection) ky lai bang CA cua no ma may chua tin.
#
# Vi sao kich ban nay nam trong tap ve LECH GIO?
#   Vi tren trinh duyet no cung la "man hinh do rat gieng nhau". Rat nhieu nguoi
#   thay man hinh do la nghi ngay den han cert. Ma loi moi la thu phai doc:
#       ERR_CERT_DATE_INVALID       -> thoi han  (KB2/KB3/MR1)
#       ERR_CERT_AUTHORITY_INVALID  -> chuoi tin cay (MR3 — day)
#       ERR_CERT_COMMON_NAME_INVALID-> ten mien  (MR2)
#   Ba ma loi, ba ho so benh an hoan toan khac nhau, mot mau man hinh.
#
# ⚠️ Loi chuoi tin cay KHONG lien quan gi den dong ho. Dong bo NTP khong chua
#    duoc no, va doi cert moi cung khong — phai cai CA vao trust store.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR3 — cho nginx serve selfsigned.crt (không do CA nào của lab ký)..."
dat_cert selfsigned
GIO_GIA=""

buoc "CHỮ KÝ: KHÔNG TIN ĐƯỢC NGƯỜI KÝ"
in_chu_ky
echo ""
echo "  Người ký cert này:"
docker exec $CLIENT sh -c \
  "echo | openssl s_client -connect $IP_WEB:443 -servername $TEN 2>/dev/null | sed -n '/BEGIN CERT/,/END CERT/p' | openssl x509 -noout -subject -issuer" \
  2>/dev/null | sed 's/^/    /' || true
echo ""
echo "👉 Đọc chữ ký:"
echo "   • subject == issuer  ->  cert TỰ KÝ. Không ai bảo lãnh cho nó."
echo "   • verify 18 'self-signed certificate'. LỆCH GIỜ ~0, notBefore/notAfter"
echo "     hoàn toàn bình thường — đây KHÔNG phải ca bệnh thời gian."
echo "   • Chữa đúng: cài CA vào trust store của máy/container, hoặc cấp cert"
echo "     từ một CA đã được tin. Đồng bộ NTP ở đây là vô nghĩa."
echo ""
echo "   🧠 Nếu học thuộc ĐÚNG MỘT thứ từ tập này, học bảng này:"
echo "        DATE_INVALID      -> so cert với ĐỒNG HỒ"
echo "        AUTHORITY_INVALID -> so cert với TRUST STORE"
echo "        COMMON_NAME_INVALID -> so cert với TÊN ĐANG GÕ"
