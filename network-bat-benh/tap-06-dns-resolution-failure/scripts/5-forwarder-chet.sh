#!/usr/bin/env bash
# ==============================================================================
# KB5 — RESOLVER SONG NHUNG CAM VOI MOT VUNG.  Chu ky: dig "timed out" giong KB2.
#
# Tinh huong ngoai doi: DNS noi bo cua cong ty chuyen tiep vung `noi-bo.local`
# len mot may chu khac (AD, DNS chi nhanh). May do chet. Resolver van song, van
# tra loi moi vung khac, chi rieng vung duoc chuyen tiep la im lang.
#
# ⭐ GIA TRI CHAN DOAN CUA KICH BAN NAY:
#    `dig` cho ra CHINH XAC cung mot dong loi va cung mot khoang thoi gian nhu
#    KB2 (~2000 ms, "timed out"). Nhin vao man hinh dig, ban KHONG the phan biet
#    "khong toi duoc resolver" voi "resolver khong tra loi duoc". Chi co GOC NHIN
#    PHIA SERVER moi tra loi: log co dong query hay khong.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TEN_NB=db.noi-bo.local

echo "🚨 KB5 — cau hinh dnsmasq chuyen tiep vung noi-bo.local sang $IP_MA (may da chet)..."
docker exec $DNS sh -c "cp /etc/dnsmasq/dnsmasq.conf.default $CONF && printf 'server=/noi-bo.local/%s\n' '$IP_MA' >> $CONF"
nap_lai_dns
sleep 1
xoa_log_dns

buoc "CHU KY: dig 'timed out' — SAO Y KB2"
in_chu_ky "$TEN_NB"

echo ""
echo "  --- GOC NHIN PHIA DNS SERVER (day moi la cho tach benh) ---"
log_dns 6 | sed 's/^/  /'

echo ""
echo "👉 Doc chu ky:"
echo "   • dig: 'communications error to $IP_DNS#53: timed out', bo cuoc sau ~2000 ms."
echo "     Dat canh KB2 thi hai man hinh dig GIONG NHAU tung chu (chi khac dia chi IP)."
echo "   • 'query toi server' > 0 — DAY LA DIEM TACH BENH. Goi tin DA TOI NOI."
echo "     Log server ghi ro: nhan cau hoi -> 'forwarded ... to $IP_MA' -> roi tac."
echo "     O KB2 con so nay la 0: cau hoi chua bao gio roi khoi client."
echo ""
echo "🔎 Chi tiet dang chu y — curl lai KHONG giong KB2:"
echo "     KB2: curl exit 28 sau ~3000 ms   (khong nameserver nao tra loi bat cu gi)"
echo "     KB5: curl exit  6 sau ~2000 ms   (co mot cau tra loi DUT KHOAT o dau do)"
echo "   Vi sao? Ung dung KHONG chi hoi mot ten. Voi 'search lab.local' trong"
echo "   /etc/resolv.conf, glibc hoi lan luot:"
echo "       1. $TEN_NB           -> chuyen tiep sang may chet -> im lang"
echo "       2. $TEN_NB.lab.local -> thuoc vung lab.local -> NXDOMAIN NGAY"
echo "   Nhan duoc NXDOMAIN dut khoat, glibc dung lai va bao 'khong tim thay'."
echo "   Con dig thi chi hoi DUNG cai ten ban go, khong noi them hau to nao."
echo ""
echo "🔑 Hai bai hoc:"
echo "   1. 'DNS timeout' o client CHUA noi len dieu gi. Phai hoi tiep: goi tin co"
echo "      toi duoc DNS server khong? Hai nguyen nhan, hai cach chua, mot trieu chung."
echo "   2. dig va ung dung di HAI CON DUONG KHAC NHAU. dig hoi dung ten ban go;"
echo "      ung dung con thu them cac hau to trong 'search'. Ket qua co the khac nhau."
echo ""
echo "   Doi chung — cung luc do, vung lab.local VAN CHAY BINH THUONG:"
echo "     $TEN -> $(ip_theo_dig)"
echo "   Resolver KHONG chet. Chi mot vung bi cam. Neu ban ket luan 'DNS server chet'"
echo "   roi di khoi dong lai no, ban da chua nham benh."
echo ""
echo "👉 Chan doan: ./scripts/test.sh $TEN_NB"
echo "   (PHAI truyen ten — test.sh mac dinh hoi $TEN, vung lab.local van khoe)"
