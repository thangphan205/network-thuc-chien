#!/usr/bin/env bash
# ==============================================================================
# KB3 — CLOCK SKEW THAT SU. Cert server HOAN TOAN HOP LE, DONG HO CLIENT sai.
#       Chu ky: verify 10 hoac 9, nhung LECH GIO LON.
#
# ⭐ DAY LA CA BENH TRUNG TAM CUA CA TAP.
#
# Tinh huong ngoai doi:
#   - May tram / thiet bi IoT het pin CMOS, khoi dong lai la nhay ve 2010.
#   - VM vua restore snapshot, dong ho dung o thoi diem chup.
#   - systemd-timesyncd / chronyd bi tat, hoac UDP 123 bi firewall chan (MR5).
#   - Container chay tren host bi lech gio — ca cluster cung sai mot luc.
#
# Kich ban chay BA lan, cung mot server, cung mot cert, chi doi moi dong ho:
#   tuong lai -> "certificate has expired"     (ma 10, y het KB2!)
#   qua khu   -> "certificate is not yet valid" (ma 9,  y het MR1!)
#   dung gio  -> 200 OK
#
# ⚠️ faketime chu KHONG doi dong ho container: container dung chung dong ho
#    kernel voi may that cua ban. Xem chu thich trong client/Dockerfile.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB3 — cert server GIỮ NGUYÊN hợp lệ (server.crt). Chỉ lừa đồng hồ client."
dat_cert good

# ------------------------------------------------------------------------------
# Ba moc thoi gian chon co chu dich:
#   2035 — sau notAfter cua server.crt (~2028). Du xa de khong bao gio "hen gio".
#   2020 — truoc notBefore. Moc kinh dien cua may het pin CMOS.
#   ""   — dong ho that.
# ------------------------------------------------------------------------------
for MOC in "2035-01-01 00:00:00|ĐỒNG HỒ CHẠY VƯỢT LÊN TƯƠNG LAI (2035)" \
           "2020-01-01 00:00:00|ĐỒNG HỒ TỤT VỀ QUÁ KHỨ (2020) — hết pin CMOS" \
           "|ĐỒNG HỒ ĐÚNG GIỜ (đã đồng bộ NTP)"; do
    GIO_GIA="${MOC%%|*}"
    buoc "CHỮ KÝ: ${MOC##*|}"
    in_chu_ky
done
GIO_GIA=""

echo ""
echo "👉 Đọc chữ ký:"
echo "   • Ba lần chạy ở trên dùng CHUNG MỘT server, CHUNG MỘT cert, cùng còn hạn."
echo "     Thứ duy nhất thay đổi là đồng hồ. Và nó đẻ ra ba kết quả khác hẳn nhau."
echo ""
echo "   • Đồng hồ VƯỢT LÊN  -> 'certificate has expired'   (mã 10)"
echo "     Mã này GIỐNG HỆT KB2. Nhưng ở KB2 lệch giờ ~0, còn ở đây lệch +8 năm."
echo "     Độ lệch giờ là thứ DUY NHẤT tách được hai ca bệnh."
echo ""
echo "   • Đồng hồ TỤT HẬU   -> 'certificate is not yet valid' (mã 9)"
echo "     Mã này giống hệt MR1 (cert cấp nhầm ngày tương lai). Cùng một cách tách."
echo ""
echo "   • Ngoài đời bạn KHÔNG chạy được cả ba lần như thế này. Bạn chỉ có MỘT"
echo "     kết quả, và phải tự hỏi: 'đồng hồ máy này đang là mấy giờ?'"
echo "     Hai lệnh phải gõ TRƯỚC khi gõ bất kỳ lệnh nào khác:"
echo "         date -u                          # đồng hồ máy đang báo lỗi"
echo "         curl -sI http://<server>/ | grep -i ^date   # đồng hồ phía server"
echo "     Header 'Date:' của HTTP không cần TLS, nên nó vẫn đọc được NGAY CẢ KHI"
echo "     TLS đang hỏng. Đây là nguồn giờ đối chiếu rẻ nhất mà ai cũng có."
