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

echo "🔧 [1/5] Khoi dong toan bo lab..."
docker compose up -d --build >/dev/null

echo "🔧 [2/5] Don sach dau vet cua canh truoc..."
# Reset phai dut khoat: cac kich ban truoc co the de lai
#   - zone bi sua (KB6, KB8)          - forwarder chet trong dnsmasq.conf (KB5)
#   - dnsmasq bi giet (KB3)           - dong de trong /etc/hosts (KB7)
#   - nscd dang cache IP cu (KB8)     - resolv.conf tro IP ma (KB2)
docker exec $DNS sh -c "cp /etc/dnsmasq/dnsmasq.conf.default $CONF; cp /etc/dnsmasq/zone-hosts.default $ZONE"
xoa_hosts_lab
docker exec $CLIENT sh -c "pkill -x nscd 2>/dev/null; rm -f /var/run/nscd/* /var/db/nscd/* 2>/dev/null; true" || true
# web-cu co the dang bi dung tu KB6 phan 2
docker start $WEB_CU >/dev/null 2>&1 || true
docker start $WEB    >/dev/null 2>&1 || true

echo "🔧 [3/5] Khoi dong lai dnsmasq voi cau hinh chuan..."
nap_lai_dns

echo "🔧 [4/5] Tro /etc/resolv.conf cua client ve DNS server cua lab ($IP_DNS)..."
# Phai dat lai bang tay chu khong dua vao `dns:` trong compose: neu hoc vien
# lo `docker compose restart client` giua buoi, resolv.conf se ve mac dinh —
# nhung neu KB2 vua ghi de no thi khong co gi keo no ve.
dat_resolv "$IP_DNS"

echo "🔧 [5/5] Kiem tra trang thai khoe..."
sleep 1
IP=$(ip_theo_dig)
if [ "$IP" != "$IP_WEB" ]; then
    echo "❌ $TEN phan giai ra '${IP:-(khong ra)}' thay vi $IP_WEB."
    echo "   Kiem tra: ./scripts/xem-log-dns.sh"
    exit 1
fi
IFS='|' read -r CODE RIP RC <<<"$(curl_thu)"
if [ "$CODE" != "200" ]; then
    echo "❌ curl http://$TEN tra ve http_code=$CODE curl_exit=$RC (mong doi 200)."
    exit 1
fi

echo ""
echo "✅ Trang thai binh thuong da san sang."
echo "   $TEN  ->  $IP   (HTTP $CODE tu $RIP)"
echo "   Trang: $(noi_dung_trang)"
echo ""
echo "👉 Mo terminal thu 2 — may do phia client:"
echo "   docker exec -it $CLIENT monitor.sh"
echo "👉 Mo terminal thu 3 — goc nhin phia DNS server:"
echo "   ./scripts/xem-log-dns.sh"
echo "   (KHONG dung 'docker compose logs dns': dnsmasq khong phai PID 1 nen"
echo "    lenh do bat duoc 0 dong — xem chu thich trong dns/dnsmasq.conf)"
