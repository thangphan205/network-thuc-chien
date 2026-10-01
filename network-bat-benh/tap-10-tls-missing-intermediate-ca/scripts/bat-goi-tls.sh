#!/usr/bin/env bash
# ==============================================================================
# BAT GOI TIN TLS trong container client roi ghi ra .pcap de mo bang Wireshark.
#
#   ./scripts/bat-goi-tls.sh [so_giay] [12|13]
#       so_giay : thoi luong bat (mac dinh 12)
#       12|13   : ep phien ban TLS. MAC DINH la 12 — doc ky phan duoi de hieu
#                 vi sao ep TLS 1.2 lai la lua chon DUNG cho muc dich HOC.
#
# Bat TRONG container chu khong bat tren card mang cua may that: goi tin cua lab
# khong bao gio ra khoi bridge, tren macOS/Windows ban khong soi duoc bang
# Wireshark cai san. Bat trong container thi chay giong nhau tren moi HDH.
#
# ==============================================================================
# ⚠️ DIEU QUAN TRONG NHAT VE WIRESHARK TRONG TAP NAY — DOC TRUOC KHI BAT
#
#   Wireshark KHONG cho ban thay "chuoi tin cay bi dut".
#
#   Viec xac thuc chuoi xay ra HOAN TOAN BEN TRONG client, sau khi goi tin da
#   den noi. Tren day khong he co goi tin nao ten la "chain error". Cai ban thay
#   chi la:
#       - ban tin Certificate (server gui bao nhieu cert — DEM DUOC)
#       - roi client gui Alert: unknown_ca / bad_certificate, hoac dong ket noi
#
#   Nghia la Wireshark tra loi duoc cau "SERVER GUI GI", va KHONG tra loi duoc
#   cau "CLIENT NGHI GI VE CAI DO". Ma toan bo tap nay xoay quanh cau thu hai.
#   Do la ly do cong cu chinh cua tap la `openssl s_client` (chay TRONG client,
#   doc duoc so depth) chu khong phai Wireshark.
#
#   Nhung co DUNG MOT thu Wireshark lam tot hon moi cong cu khac: cho ban thay
#   ban tin Certificate PHINH TO ra khi chuoi dai them. Do la ly do script nay
#   ton tai.
#
# ==============================================================================
# ⚠️ VI SAO PHAI EP TLS 1.2 — NEU KHONG, WIRESHARK KHONG THAY GI CA
#
#   nginx 1.29 mac dinh dam phan TLS 1.3. Va trong TLS 1.3, ban tin Certificate
#   duoc GUI SAU khi hai ben da co khoa phien — tuc la NO DUOC MA HOA.
#
#   Hau qua rat cu the: ban mo Wireshark, go dung filter `tls.handshake.type == 11`,
#   va nhan duoc MOT DANH SACH RONG. Khong phai lab hong — chi la cai ban muon
#   nhin da nam trong phan ma hoa.
#
#   TLS 1.2 gui Certificate o dang RO, ngay sau ServerHello. Vi vay muon HOC
#   bang mat thi phai ep 1.2. Ngoai doi thi nguoc lai: 1.3 tot hon, va chinh
#   viec no giau chuoi cert la mot ly do khien tap nay phai dua vao
#   `openssl s_client` (chay TRONG client, nhin duoc SAU khi giai ma) chu khong
#   dua vao Wireshark.
#
#   Muon tu kiem chung: chay `./scripts/bat-goi-tls.sh 12 13` roi thu lai dung
#   filter do. Danh sach se rong. Do la bai hoc, khong phai loi.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

GIAY=${1:-12}
VER=${2:-12}
TEP="tap08-tls1${VER#1}-$(date +%H%M%S).pcap"

if [ "$VER" = "12" ]; then
    EP="-tls1_2"; GHI_CHU="TLS 1.2 — bản tin Certificate ở dạng RÕ, nhìn được"
else
    EP="-tls1_3"; GHI_CHU="TLS 1.3 — bản tin Certificate ĐÃ MÃ HÓA, Wireshark KHÔNG thấy"
fi

echo "📡 Bắt gói tin ${GIAY}s trong container client -> $TEP"
echo "   $GHI_CHU"
docker exec -d $CLIENT sh -c "timeout $GIAY tcpdump -i any -w /tmp/cap.pcap 'host $IP_WEB and port 443' 2>/dev/null"
sleep 1

echo "   Sinh một lần bắt tay TLS (ép $EP)..."
_trong_client "echo | openssl s_client -connect $IP_WEB:443 -servername $TEN -CAfile $TRUST $EP >/dev/null 2>&1; true"

echo "   Chờ tcpdump ghi xong..."
sleep "$GIAY"
docker cp "$CLIENT:/tmp/cap.pcap" "./$TEP" >/dev/null 2>&1
echo "✅ Đã ghi: $TEP  ($(du -h "$TEP" | cut -f1))"
echo ""
if [ "$VER" = "12" ]; then
    echo "👉 Mở bằng Wireshark, lọc:  tls.handshake.type == 11"
    echo "   (11 = Certificate). Xem cột Length của bản tin đó."
else
    echo "👉 Mở bằng Wireshark, lọc:  tls.handshake.type == 11"
    echo "   ⚠️ Bạn sẽ thấy DANH SÁCH RỖNG. Đó là đúng: TLS 1.3 mã hóa bản tin"
    echo "      Certificate. Chạy lại với tham số 12 để nhìn thấy nó."
fi
echo ""
echo "📏 SO SÁNH KÍCH THƯỚC BẢN TIN Certificate — bài đo đáng làm nhất của tập:"
echo ""
printf "   %-26s %-8s %s\n" "CHUỖI" "#CERT" "TỔNG BYTES CERT GỬI RA DÂY"
for c in chuoi_thieuint chuoi_daydu chuoi_thuaroot; do
    B=$(docker exec $CLIENT sh -c "wc -c < /etc/ssl/lab/$c.crt" 2>/dev/null | tr -d ' ')
    N=$(docker exec $CLIENT sh -c "grep -c 'BEGIN CERTIFICATE' /etc/ssl/lab/$c.crt" 2>/dev/null | tr -d ' ')
    printf "   %-26s %-8s %s\n" "$c.crt" "$N" "${B:-?}"
done
echo ""
echo "   👉 KB2 (1 cert) nhẹ nhất — và hỏng. MR2 (3 cert) nặng nhất — và chạy."
echo "      'Nhỏ hơn' không hề có nghĩa là 'tốt hơn' ở đây: cái bị cắt đi chính"
echo "      là mắt xích client cần để nối được chuỗi."
