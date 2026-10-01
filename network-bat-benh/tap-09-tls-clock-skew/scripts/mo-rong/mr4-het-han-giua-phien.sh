#!/usr/bin/env bash
# ==============================================================================
# MR4 — CERT HET HAN GIUA CHUNG.  Chu ky: phien CU van song, phien MOI thi chet.
#
# Kich ban nay tra loi cau hoi ma gan nhu buoi van hanh nao cung gap:
#
#   "Cert het han luc 2h sang. Sao toi 9h30 khach hang moi bao loi?
#    Va sao trong luc do he thong giam sat van bao xanh?"
#
# Vi thoi han cert duoc kiem tra DUNG MOT LAN — luc bat tay. Phien da mo thi
# khong ai kiem tra lai. Nen luc cert het han:
#   - cac ket noi DANG MO  : chay tiep binh thuong, khong ai bi dut,
#   - cac ket noi MOI      : chet ngay.
# He thong "chet dan" theo nhip khach hang mo ket noi moi, chu khong chet mot
# phat. Monitor giu ket noi keep-alive lau se bao xanh rat lau sau khi da hong.
#
# Cach lam trong lab: sinh mot cert chi song $GIAY_SONG giay, mo mot phien TLS,
# GIU nguyen phien do, cho cert het han, roi gui request tren chinh phien cu.
#
# ⏱️ Kich ban nay MAT ~$((GIAY_SONG + 25)) GIAY. Day la kich ban duy nhat cua tap
#    can cho lau — vi no dang do mot hien tuong theo thoi gian that.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

GIAY_SONG=${1:-60}      # cert song bao nhieu giay
GIAY_CHO=$((GIAY_SONG + 15))

echo "🚨 MR4 — sinh một cert chỉ sống $GIAY_SONG giây rồi cho nginx serve nó..."
# Sinh LUC CHAY, khong sinh luc `up`: neu sinh san thi den luc hoc vien chay toi
# day no da het han tu doi nao, va kich ban mat sach y nghia.
docker compose run --rm certgen short "$GIAY_SONG" 2>&1 | sed 's/^/   /'
dat_cert shortlived
GIO_GIA=""

buoc "MỐC 0 — cert vừa sinh, CÒN HẠN"
in_chu_ky

buoc "MỞ MỘT PHIÊN TLS VÀ GIỮ NGUYÊN NÓ"
echo "  Chạy trong client: phien-dai.sh $GIAY_CHO"
echo "  (bắt tay bây giờ, gửi request sau $GIAY_CHO giây — lúc cert đã hết hạn)"
docker exec -d $CLIENT sh -c "phien-dai.sh $GIAY_CHO $TEN $IP_WEB > /tmp/phien.log 2>&1"

sleep 6
echo ""
echo "  --- trạng thái phiên sau 6 giây ---"
docker exec $CLIENT cat /tmp/phien.log 2>/dev/null | sed 's/^/  /' || true

echo ""
echo "  ⏳ Đợi cert hết hạn ($((GIAY_SONG - 6)) giây nữa)..."
sleep $((GIAY_SONG - 6 + 5))

buoc "MỐC 1 — CERT ĐÃ HẾT HẠN. Thử một kết nối MỚI"
in_chu_ky
echo ""
echo "  👉 Kết nối MỚI: chết. Đây là thứ khách hàng nhìn thấy."

buoc "MỐC 2 — còn PHIÊN CŨ mở từ trước thì sao?"
echo "  Đợi phien-dai.sh gửi request trên phiên cũ rồi in kết quả..."
for _ in $(seq 1 40); do
    if docker exec $CLIENT grep -q "Phản hồi nhận được" /tmp/phien.log 2>/dev/null; then break; fi
    sleep 2
done
docker exec $CLIENT cat /tmp/phien.log 2>/dev/null | sed 's/^/  /' || true

echo ""
echo "👉 Đọc chữ ký:"
echo "   • Phiên mở TRƯỚC khi cert hết hạn: vẫn trả về 200 SAU khi cert hết hạn."
echo "     Bắt tay dùng -verify_return_error, nên nếu cert xấu lúc bắt tay thì"
echo "     phiên đã đứt ngay từ đầu. Nó không đứt => lúc đó cert THẬT SỰ còn hạn,"
echo "     và sau đó KHÔNG AI kiểm tra lại."
echo "   • Kết nối mới: chết ngay. Hai sự thật này tồn tại CÙNG LÚC."
echo ""
echo "   🧠 Hệ quả thực tế:"
echo "     1. 'Dịch vụ vẫn chạy' KHÔNG chứng minh được cert còn hạn. Phải kiểm tra"
echo "        bằng một kết nối MỚI:  openssl s_client / curl, đừng dựa vào trang"
echo "        web đang mở sẵn trong tab."
echo "     2. Giám sát phải mở KẾT NỐI MỚI mỗi vòng. Health-check dùng keep-alive"
echo "        sẽ báo xanh hàng giờ sau khi cert đã hết hạn."
echo "     3. Đó cũng là lý do sự cố cert thường bùng ra vào GIỜ CAO ĐIỂM chứ"
echo "        không phải đúng thời điểm hết hạn: giờ cao điểm là lúc có nhiều"
echo "        kết nối mới nhất."
echo ""
echo "   Reset: ./scripts/0-setup.sh"
