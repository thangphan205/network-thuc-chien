#!/usr/bin/env bash
# ==============================================================================
# KB8 — BO DEM GIU IP CU.  ⭐ Chu ky: "sua roi ma van sai".
#
# Tinh huong ngoai doi: ban chuyen server, sua ban ghi A, dig kiem tra thay dung
# IP moi. Nhung ung dung tren may van vao dia chi cu. Ban restart ung dung —
# van the. Ban do cho "TTL chua het" roi ngoi cho... trong khi thu pham nam ngay
# tren chinh may do.
#
# Co che: nscd (hoac systemd-resolved, hoac chinh JVM) dem ket qua getaddrinfo().
# `dig` KHONG di qua nscd — no ban goi UDP thang toi nameserver. Vi vay dig thay
# du lieu MOI trong khi ung dung van an du lieu CU. Hai cong cu, hai su that.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

# ./scripts/8-cache-cu.sh --chua  -> chi chay phan chua roi thoat
if [ "${1:-}" = "--chua" ]; then
    echo "🩺 Xoa bo dem hosts cua nscd..."
    docker exec $CLIENT nscd -i hosts >/dev/null 2>&1 || true
    sleep 1
    echo "   IP theo NSS/app bay gio: $(ip_theo_nss)"
    echo "   IP theo dig            : $(ip_theo_dig)"
    echo "✅ Hai con so da khop. Bo dem duoc xoa NGAY, khong phai ngoi doi het TTL."
    exit 0
fi

echo "🚨 KB8 — bat nscd (bo dem DNS cua he thong) va nap ten vao cache..."
docker exec $CLIENT sh -c "pkill -x nscd 2>/dev/null; rm -f /var/db/nscd/* 2>/dev/null; nscd" >/dev/null 2>&1 || true
sleep 1
docker exec $CLIENT sh -c 'pgrep -x nscd >/dev/null && echo "   nscd dang chay, TTL hosts = 60 giay"'
# ⚠️ Phai ham nong cache bang CA HAI duong: `getent hosts` (tra cuu IPv4 thuan)
#    va mot lan `curl` that (getaddrinfo voi AF_UNSPEC). nscd dem hai loai truy
#    van nay o HAI KHOA KHAC NHAU — chi ham nong mot ben thi ben kia van di hoi
#    moi, va ca benh se tu mau thuan ngay tren man hinh.
docker exec $CLIENT getent hosts "$TEN" >/dev/null 2>&1 || true
docker exec $CLIENT sh -c "curl -s -o /dev/null --max-time 3 'http://$TEN/'" >/dev/null 2>&1 || true
echo "   Da nap vao cache: $TEN -> $(ip_theo_nss)"

echo ""
echo "🚨 Bay gio doi ban ghi tren DNS server sang $IP_WEB_CU (nhu vua chuyen server)..."
xoa_log_dns
doi_ban_ghi "$TEN" "$IP_WEB_CU"
sleep 1

buoc "CHU KY: dig thay IP MOI, ung dung van dung IP CU"
in_chu_ky
echo ""
echo "👉 Doc chu ky:"
echo "   • IP theo dig     = $IP_WEB_CU  (MOI — DNS server da cap nhat xong)"
echo "   • IP theo NSS/app = $IP_WEB  (CU — nscd van dang giu ket qua truoc do)"
echo "   • Hai dong LECH NHAU, giong KB7. Nhung o KB7 /etc/hosts co dong thua,"
echo "     con o day /etc/hosts SACH:"
docker exec $CLIENT sh -c "grep -c 'lab.local' /etc/hosts 2>/dev/null; true" | head -1 | sed 's/^/       so dong lab.local trong \/etc\/hosts: /'
echo "     -> khong phai hosts. Thu pham la BO DEM."

echo ""
echo "  --- Bang chung: khoi dong lai ung dung KHONG cuu duoc ---"
IFS='|' read -r _c RIP2 _r <<<"$(curl_thu)"
echo "     Chay curl lan nua, mot tien trinh HOAN TOAN MOI -> ket noi toi: ${RIP2:-(khong toi dau)}"
echo "     Van IP cu. Cache khong nam trong ung dung, no nam trong nscd —"
echo "     giet ung dung bao nhieu lan cung vo ich."

echo ""
echo "  --- CACH CHUA (chua chay — de ban tu chay va tu quan sat) ---"
echo "     docker exec $CLIENT nscd -i hosts        # xoa bo dem hosts NGAY"
echo "     (hoac cho het 60 giay TTL, hoac: pkill nscd)"
echo ""
echo "     Chay san bang:  ./scripts/8-cache-cu.sh --chua"
echo ""
echo "  ℹ️  Ca benh duoc GIU NGUYEN de ban chay ./scripts/test.sh va thay no tu"
echo "     chan doan ra KB8. Chay ./scripts/0-setup.sh de reset."

echo ""
echo "🔑 Bai hoc:"
echo "   • 'dig ra dung roi ma van loi' KHONG phai chuyen hoang duong. No co nghia"
echo "     la giua ung dung va DNS server con mot lop dem ma dig khong di qua."
echo "   • Cac lop dem hay gap: nscd, systemd-resolved (127.0.0.53), dnsmasq tren"
echo "     may, bo dem cua chinh runtime (JVM cache DNS VINH VIEN neu"
echo "     networkaddress.cache.ttl = -1), va bo dem cua trinh duyet."
echo "   • Ubuntu 24.04+: lop dem mac dinh la systemd-resolved (127.0.0.53)."
echo "     dig KHONG @ cung di qua no -> dung: dig @<IP DNS that> $TEN"
echo "     Xoa bo dem: sudo resolvectl flush-caches"
echo "   • Lenh kiem tra dung van la: getent hosts $TEN"
echo "     Neu no lech voi dig -> di tim lop dem, dung do loi cho DNS server."
