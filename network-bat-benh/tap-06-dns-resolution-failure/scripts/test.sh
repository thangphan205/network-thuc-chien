#!/usr/bin/env bash
# ==============================================================================
# CHAN DOAN: di tu ngoai vao trong, xac dinh o benh nam o dau.
#
# Thu tu 7 buoc khong phai ngau nhien — no la dung quy trinh ban nen lam ngoai
# doi khi nhan duoc cau than "ping IP thi duoc ma go ten mien thi chet".
# Moi buoc deu in KET QUA va noi ro ket qua do LOAI TRU duoc gia thuyet nao.
#
# Chay duoc o BAT KY trang thai nao cua lab (khoe hay dang co benh).
#   ./scripts/test.sh [ten_mien]
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TEN_HOI=${1:-$TEN}

buoc "[BUOC 1] Tang 3 con song khong? — ping THANG IP, khong qua ten mien"
if docker exec $CLIENT ping -c2 -W1 $IP_WEB >/dev/null 2>&1; then
    echo "  ✅ ping $IP_WEB: THONG."
    echo "  👉 Duong truyen, route, firewall o L3 deu OK. Moi loi tu day tro di"
    echo "     KHONG phai loi mang — dung di soi day, soi switch, soi iptables."
    L3=1
else
    echo "  ❌ ping $IP_WEB: KHONG THONG."
    echo "  👉 Dung lai o day. Chua den luot DNS — di sua L2/L3 truoc."
    L3=0
fi

buoc "[BUOC 2] Client dang hoi AI? — /etc/resolv.conf"
docker exec $CLIENT cat /etc/resolv.conf 2>/dev/null | sed 's/^/  /'
NS=$(docker exec $CLIENT sh -c "awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf" 2>/dev/null | tr -d '\r')
echo ""
if [ "$NS" = "$IP_DNS" ]; then
    echo "  ✅ nameserver = $IP_DNS — dung DNS server cua lab."
else
    echo "  ❌ nameserver = ${NS:-(khong co)} — KHONG phai $IP_DNS cua lab."
    echo "  👉 Manh moi manh nhat. Doc tiep de xem no im lang hay tu choi."
fi

buoc "[BUOC 3] UNG DUNG that su dung IP nao? — getent hosts"
NSS=$(ip_theo_nss "$TEN_HOI")
echo "  getent hosts $TEN_HOI  ->  ${NSS:-(khong ra gi)}"
echo "  👉 Day la duong ma ung dung THAT SU di: /etc/hosts -> nscd -> DNS."
echo "     Khong phai duong ma dig di. Kiem tra bang getent, khong phai bang dig."
echo "  ℹ️  Ubuntu 24.04+ (resolv.conf = 127.0.0.53): dig khong @ di QUA bo dem"
echo "     systemd-resolved. Hoi thang: dig @<IP trong 'resolvectl status'> <ten>."

buoc "[BUOC 4] DNS SERVER noi gi? — dig (bo qua hosts va nscd)"
RAW=$(dig_full "$TEN_HOI")
ST=$(dig_status_tu "$RAW"); QT=$(dig_qtime_tu "$RAW")
WALL=$(dig_wall_tu "$RAW"); DIP=$(dig_ip_tu "$RAW")
echo "  status     : $ST"
if [ "$ST" = "KHONG-TRA-LOI" ]; then
    echo "  loi        : $(dig_loi_tu "$RAW")"
    echo "  bo cuoc sau: ${WALL} ms"
    case "$(dig_loi_tu "$RAW")" in
        *"connection refused"*)
            echo "  👉 CO ai do tra loi ngay: kernel may DNS bao cong 53 DANG DONG."
            echo "     May song, DICH VU chet. -> KB3." ;;
        *"timed out"*)
            echo "  👉 KHONG ai tra loi trong ${WALL} ms. Hai kha nang, chua phan biet duoc:"
            echo "     goi tin chua toi noi (KB2)  HOAC  toi noi ma server khong dap (KB5)."
            echo "     BUOC 6 se tra loi." ;;
        *)  echo "  👉 Loi bat thuong — doc ky dong tren." ;;
    esac
else
    echo "  Query time : ${QT} ms"
    echo "  IP tra ve  : ${DIP:-(khong co ban ghi A)}"
    if [ "$ST" = "NXDOMAIN" ]; then
        echo "  👉 Server SONG va DA tra loi — cau tra loi la 'ten nay khong ton tai'."
        echo "     ${QT} ms = nhanh = co nguoi dap. Doi lap hoan toan voi timeout."
        echo "     Day KHONG phai su co mang. Go sai ten, hoac thieu ban ghi. -> KB4."
    fi
fi

buoc "[BUOC 5] SO SANH buoc 3 voi buoc 4 — buoc quan trong nhat"
echo "  Ung dung dung (NSS): ${NSS:-(khong ra)}"
echo "  DNS server tra ve  : ${DIP:-(khong ra)}"
echo ""
if [ -n "$NSS" ] && [ -n "$DIP" ] && [ "$NSS" != "$DIP" ]; then
    echo "  ❌ LECH NHAU. Thu pham nam TREN MAY CLIENT, khong phai tren DNS server."
    HOSTS=$(docker exec $CLIENT sh -c "grep -c '$TEN_HOI\$' /etc/hosts 2>/dev/null; true" | head -1 | tr -d '\r')
    if [ "${HOSTS:-0}" != "0" ]; then
        echo "     -> /etc/hosts co dong de len ten nay:"
        docker exec $CLIENT grep "$TEN_HOI\$" /etc/hosts 2>/dev/null | sed 's/^/        /'
        echo "     -> KB7. Chua: xoa dong do."
    elif docker exec $CLIENT pgrep -x nscd >/dev/null 2>&1; then
        echo "     -> /etc/hosts sach, nhung nscd DANG CHAY va giu ket qua cu."
        echo "     -> KB8. Chua: nscd -i hosts (dung ngoi doi TTL)."
    else
        echo "     -> Khong thay hosts lan nscd. Tim tiep cac lop dem khac"
        echo "        (systemd-resolved, cache cua runtime)."
        echo "        Ubuntu 24.04+: sudo resolvectl flush-caches"
    fi
elif [ -n "$DIP" ]; then
    echo "  ✅ KHOP NHAU. Khong ai chen ngang giua DNS va ung dung."
    if [ "$DIP" != "$IP_WEB" ]; then
        echo "  ❌ NHUNG day KHONG phai dia chi dung cua dich vu ($IP_WEB)."
        echo "     DNS tra loi tron tru — va tra ve SAI DIA CHI. -> KB6."
        echo "     Chua: sua ban ghi A tren DNS server."
    fi
fi

buoc "[BUOC 6] Goi tin CO TOI DUOC DNS server khong? — log phia server"
Q=$(dem_query_o_server)
LOI=$(dig_loi_tu "$RAW")
echo "  So dong query[...] trong $LOG_DNS: $Q"
echo ""
# Ket luan o buoc nay CHI co nghia khi buoc 4 that bai. Neu dig da tra loi binh
# thuong thi so query > 0 la chuyen duong nhien, khong to cao ai ca.
if [ "$ST" != "KHONG-TRA-LOI" ]; then
    echo "  👉 Buoc 4 da co cau tra loi, nen con so nay chi xac nhan server dang lam viec."
    echo "     Buoc 6 chi dung de PHA AN khi buoc 4 bao 'timed out'."
elif [ "${Q:-0}" = "0" ]; then
    case "$LOI" in
        *"connection refused"*)
            echo "  👉 SO KHONG query — dung nhu mong doi: tien trinh DNS da chet nen"
            echo "     khong ai ghi log duoc. Ket luan van la KB3 (buoc 4 da chi ro)." ;;
        *)  echo "  👉 SO KHONG. Cau hoi CHUA TUNG toi duoc server."
            echo "     Sai dia chi nameserver, hoac firewall chan UDP 53. -> KB2." ;;
    esac
else
    echo "  👉 CO query — goi tin DA TOI NOI, server nhan duoc cau hoi."
    echo "     Ma buoc 4 van bao 'timed out' => loi nam BEN TRONG server"
    echo "     (forwarder chet, vung bi cam). -> KB5, KHONG phai KB2."
    echo ""
    echo "  4 dong log cuoi:"
    log_dns 4 | sed 's/^/    /'
fi

buoc "[BUOC 7] Goi dich vu THAT — va kiem tra dung MAY chua"
IFS='|' read -r CODE RIP RC <<<"$(curl_thu "$TEN_HOI")"
PAGE=$(noi_dung_trang "$TEN_HOI")
echo "  curl http://$TEN_HOI/  ->  http_code=$CODE  exit=$RC  ket noi toi ${RIP:-(khong toi dau)}"
echo "  trang nhan duoc        :  ${PAGE:-(khong co)}"
echo ""
case "$RC" in
    0)  if [ "$RIP" = "$IP_WEB" ]; then
            echo "  ✅ HTTP $CODE tu dung may $IP_WEB. Dich vu khoe."
        else
            echo "  ⚠️  HTTP $CODE — NHUNG tu $RIP, khong phai $IP_WEB."
            echo "     Day la ca nguy hiem nhat: giam sat uptime bao MAU XANH trong khi"
            echo "     nguoi dung dang xem nham server. -> KB6-A hoac KB7 hoac KB8."
        fi ;;
    6)  echo "  ❌ curl exit 6 'Could not resolve host' — chet o khau PHAN GIAI."
        echo "     Chu y: exit 6 xuat hien o CA KB3 (bi tu choi) LAN KB4 (NXDOMAIN)."
        echo "     curl KHONG du de chan doan. Doc lai buoc 4." ;;
    28) echo "  ❌ curl exit 28 TIMEOUT. Nhung timeout o KHAU NAO?"
        echo "     Neu buoc 4 khong ra IP  -> chet luc PHAN GIAI  (KB2)."
        echo "     Neu buoc 4 CO ra IP     -> phan giai xong roi, chet luc KET NOI TCP"
        echo "                                toi dia chi do (KB6-B). Kiem bang curl -v:"
        echo "                                co in duoc dong 'Trying <ip>:80' khong." ;;
    7)  echo "  ❌ curl exit 7 CONNECTION REFUSED — ten phan giai OK, may co that,"
        echo "     nhung khong ai nghe cong 80. Khong phai ca benh DNS." ;;
    *)  echo "  ❌ curl exit $RC." ;;
esac

echo ""
echo "=========================================="
echo "🔑 BANG VAN TAY — dan len tuong"
echo "=========================================="
cat <<'BANG'
  dig                      curl      NSS vs dig   -> Ca benh
  ------------------------ --------- ------------ ---------------------------
  NOERROR, IP dung         200       khop         KHOE
  timed out (~2000ms)      exit 28   -            KB2 resolver khong toi duoc
                                                  (log server: 0 query)
  timed out (~2000ms)      exit 6    -            KB5 forwarder chet
                                                  (log server: CO query)
  connection refused (~20ms) exit 6  -            KB3 dich vu DNS chet
  NXDOMAIN (~0ms)          exit 6    -            KB4 khong co ban ghi
  NOERROR, IP SAI          200/28    khop         KB6 DNS tra sai dia chi
  NOERROR, IP dung         200       LECH         KB7 /etc/hosts de len
  NOERROR, IP MOI          200       LECH (cu)    KB8 bo dem giu IP cu
BANG
[ "$L3" = "0" ] && echo "" && echo "⚠️  Nhac lai: BUOC 1 that bai. Moi ket luan tren deu vo nghia khi L3 dang chet."
exit 0
