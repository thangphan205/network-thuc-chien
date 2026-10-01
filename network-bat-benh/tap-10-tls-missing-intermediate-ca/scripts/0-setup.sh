#!/usr/bin/env bash
# ==============================================================================
# Dua lab ve trang thai BINH THUONG:
#   nginx gui chuoi day du (leaf + intermediate), trust store cua client CO root
#   cua lab, nginx dang chay.
# Chay lai script nay bat cu luc nao de reset sach lab.
#
# Reset phai dut khoat vi cac kich ban truoc co the de lai:
#   - root CA DA BI GO khoi trust store            (KB3)
#   - nginx DA CHET vi chuoi dao nguoc             (MR1)
#   - mot chuoi hong nao do trong nginx.conf       (KB2/4/5/7)
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🔧 [1/5] Khởi động toàn bộ lab..."
docker compose up -d --build >/dev/null 2>&1

echo "🔧 [2/5] Cài lại root CA của lab vào trust store của client..."
# KB3 go root ra. Khong cai lai thi moi kich ban sau deu bao num=20 depth=1 —
# va hoc vien se tuong minh gap ca benh cua KB3 o khap moi noi.
cai_root
echo "     trust store  ->  $(co_root)"

echo "🔧 [3/5] Đặt lại CHUỖI ĐẦY ĐỦ cho nginx..."
dat_chuoi good

echo "🔧 [4/5] Kiểm tra nginx đã khởi động lại..."
if [ "$(nginx_song)" != "ĐANG CHẠY" ]; then
    echo "❌ nginx không khởi động được. Log:"
    nginx_ly_do_chet | sed 's/^/     /'
    exit 1
fi

echo "🔧 [5/5] Kiểm tra trạng thái khỏe..."
RAW=$(_bat_tay)
IFS='|' read -r NUM DEPTH MSG <<<"$(verify_chi_tiet "$RAW")"
if [ "$NUM" != "0" ]; then
    echo "❌ openssl verify trả về num=$NUM depth=$DEPTH ($MSG), mong đợi num=0."
    echo "   Soi thêm: ./scripts/xem-chuoi.sh"
    exit 1
fi
IFS='|' read -r CODE RC CMSG <<<"$(curl_thu)"
if [ "$CODE" != "200" ]; then
    echo "❌ curl https://$TEN trả về http=$CODE exit=$RC"
    echo "   $CMSG"
    exit 1
fi

echo ""
echo "✅ Trạng thái bình thường đã sẵn sàng."
echo "   $TEN  ->  HTTP $CODE, openssl verify num=$NUM"
echo "   Server gửi $(so_cert_gui "$RAW") cert:"
chuoi_gui_ra "$RAW"
echo ""
echo "👉 Mở terminal thứ 2 — máy đo phía client:"
echo "   docker exec -it $CLIENT monitor.sh"
echo "👉 Mở terminal thứ 3 — góc nhìn phía server (chuỗi đang thực sự gửi ra dây):"
echo "   ./scripts/xem-chuoi.sh"
echo ""
echo "👉 Muốn soi bằng TRÌNH DUYỆT trên máy thật? Đọc mục 'Xem bằng trình duyệt'"
echo "   trong README — phải thêm /etc/hosts và import root CA thì mới ra đúng"
echo "   ERR_CERT_AUTHORITY_INVALID. Vào thẳng https://localhost:$PORT_HOST sẽ ra"
echo "   lỗi SAI TÊN MIỀN, một ca bệnh hoàn toàn khác (tập 09 MR2)."
