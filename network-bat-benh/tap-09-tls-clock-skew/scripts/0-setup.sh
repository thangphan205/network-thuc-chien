#!/usr/bin/env bash
# ==============================================================================
# Dung lab ve trang thai BINH THUONG:
#   nginx serve server.crt (con han, SAN dung), client khong bi chan NTP,
#   khong con phien TLS treo tu MR4, dong ho client la dong ho that.
# Chay lai script nay bat cu luc nao de reset sach lab.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🔧 [1/5] Khởi động toàn bộ lab..."
docker compose up -d --build >/dev/null 2>&1

echo "🔧 [2/5] Dọn sạch dấu vết của cảnh trước..."
# Reset phai dut khoat: cac kich ban truoc co the de lai
#   - luat iptables chan UDP 123        (MR5)
#   - tien trinh s_client con treo + FIFO (MR4)
#   - short.crt da het han nam trong ssl/ (MR4)
mo_lai_ntp
docker exec $CLIENT sh -c "pkill -f 'openssl s_client' 2>/dev/null; rm -f /tmp/req /tmp/resp /tmp/phien.log; true" >/dev/null 2>&1 || true

echo "🔧 [3/5] Đặt lại cert HỢP LỆ cho nginx..."
dat_cert good

echo "🔧 [4/5] Kiểm tra nguồn giờ thật (NTP server của lab)..."
NTP_KQ=$(ntp_ket_qua)
echo "     chronyd -Q  ->  $NTP_KQ"

echo "🔧 [5/5] Kiểm tra trạng thái khỏe..."
V=$(verify_openssl)
if [[ "$V" != 0\ \(ok\)* ]]; then
    echo "❌ openssl verify trả về '$V' (mong đợi '0 (ok)')."
    echo "   Soi thêm: ./scripts/xem-cert.sh"
    exit 1
fi
IFS='|' read -r CODE RC MSG <<<"$(curl_thu)"
if [ "$CODE" != "200" ]; then
    echo "❌ curl https://$TEN trả về http=$CODE exit=$RC"
    echo "   $MSG"
    exit 1
fi

echo ""
echo "✅ Trạng thái bình thường đã sẵn sàng."
echo "   $TEN  ->  HTTP $CODE, openssl verify $V"
echo "   Cert : $(han_cert notBefore)  ->  $(han_cert notAfter)"
echo "   Lệch giờ client/server: $(lech_doc_duoc "$(lech_giay)")"
echo ""
echo "👉 Mở terminal thứ 2 — máy đo phía client:"
echo "   docker exec -it $CLIENT monitor.sh"
echo "👉 Mở terminal thứ 3 — góc nhìn phía server (cert đang thực sự được serve):"
echo "   ./scripts/xem-cert.sh"
echo ""
echo "👉 Muốn soi bằng TRÌNH DUYỆT trên máy thật? Đọc mục 'Xem bằng trình duyệt'"
echo "   trong README — phải thêm /etc/hosts và import CA thì mới ra đúng"
echo "   ERR_CERT_DATE_INVALID. Vào thẳng https://localhost:$PORT_HOST sẽ ra"
echo "   lỗi SAI TÊN MIỀN, một ca bệnh hoàn toàn khác."
