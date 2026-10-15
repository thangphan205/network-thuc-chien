#!/usr/bin/env bash
# ==============================================================================
# Dung lab ve trang thai BINH THUONG:
#   dnsmasq chay voi zone chuan, client tro vao 172.28.6.53, /etc/hosts sach,
#   nscd tat, web va web-cu deu song.
# Chay lai script nay bat cu luc nao de reset sach lab.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🔧 [1/5] Khởi động toàn bộ lab..."
docker compose up -d --build >/dev/null 2>&1

echo "🔧 [2/5] Dọn sạch dấu vết của cảnh trước..."
# Reset phai dut khoat: cac kich ban truoc co the de lai
#   - zone bi sua (KB6, KB8)          - forwarder chet trong dnsmasq.conf (KB4)
#   - dnsmasq bi giet (KB3)           - dong de trong /etc/hosts (KB7)
#   - nscd dang cache IP cu (KB8)     - resolv.conf tro IP ma (KB2)
#   - vung cua-hang.local va dong /etc/hosts cua ca bi an (ca-bi-an.sh)
docker exec $DNS sh -c "cp /etc/dnsmasq/dnsmasq.conf.default $CONF; cp /etc/dnsmasq/zone-hosts.default $ZONE"
xoa_hosts_lab
xoa_hosts_lab "$TEN_BI_AN"
docker exec $CLIENT sh -c "pkill -x nscd 2>/dev/null; rm -f /var/run/nscd/* /var/db/nscd/* 2>/dev/null; true" || true
# web-cu co the dang bi dung tu KB6 phan 2
docker start $WEB_CU >/dev/null 2>&1 || true
docker start $WEB    >/dev/null 2>&1 || true

echo "🔧 [3/5] Khởi động lại dnsmasq với cấu hình chuẩn..."
nap_lai_dns

echo "🔧 [4/5] Trỏ /etc/resolv.conf của client về DNS server của lab ($IP_DNS)..."
# Phai dat lai bang tay chu khong dua vao `dns:` trong compose: neu hoc vien
# lo `docker compose restart client` giua buoi, resolv.conf se ve mac dinh —
# nhung neu KB2 vua ghi de no thi khong co gi keo no ve.
dat_resolv "$IP_DNS"

echo "🔧 [5/5] Kiểm tra trạng thái khỏe..."
sleep 1
IP=$(ip_theo_dig)
if [ "$IP" != "$IP_WEB" ]; then
    echo "❌ $TEN phân giải ra '${IP:-(không ra)}' thay vì $IP_WEB."
    echo "   Kiểm tra: ./scripts/xem-log-dns.sh"
    exit 1
fi
IFS='|' read -r CODE RIP RC <<<"$(curl_thu)"
if [ "$CODE" != "200" ]; then
    echo "❌ curl http://$TEN trả về http_code=$CODE curl_exit=$RC (mong đợi 200)."
    exit 1
fi

echo ""
echo "✅ Trạng thái bình thường đã sẵn sàng."
echo "   $TEN  ->  $IP   (HTTP $CODE từ $RIP)"
echo "   Trang: $(noi_dung_trang)"
echo ""
echo "👉 Mở terminal thứ 2 — máy đo phía client:"
echo "   docker exec -it $CLIENT monitor.sh"
echo "👉 Mở terminal thứ 3 — góc nhìn phía DNS server:"
echo "   ./scripts/xem-log-dns.sh"
echo "   (KHÔNG dùng 'docker compose logs dns': dnsmasq không phải PID 1 nên"
echo "    lệnh đó bắt được 0 dòng — xem chú thích trong dns/dnsmasq.conf)"
