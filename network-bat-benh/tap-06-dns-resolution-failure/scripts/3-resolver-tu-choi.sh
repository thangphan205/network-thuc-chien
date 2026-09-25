#!/usr/bin/env bash
# ==============================================================================
# KB3 — RESOLVER TU CHOI.  Chu ky: CONNECTION REFUSED.
#
# Tinh huong ngoai doi: may DNS van song, van ping duoc, nhung tien trinh named/
# dnsmasq da chet (het RAM, crash sau khi update, quen enable sau reboot).
#
# Day la ban DNS cua cap tap 01 (DROP -> im lang) vs tap 02 (REJECT -> tra loi
# tu choi ngay). Cung mot muc tieu khong phuc vu duoc, hai chu ky khac han nhau.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB3 — giet tien trinh dnsmasq (container dns VAN SONG)..."
xoa_log_dns
docker exec $DNS dns-stop
echo "   Kiem chung may van song: $(docker exec $CLIENT ping -c1 -W1 $IP_DNS >/dev/null 2>&1 && echo 'ping toi DNS server: THONG' || echo 'ping: KHONG THONG')"

buoc "CHU KY: CONNECTION REFUSED"
in_chu_ky
echo ""
echo "👉 Doc chu ky — so sanh voi KB2:"
echo "   • dig mat ~30 ms, KHONG phai 2000 ms. Co ai do tra loi ngay lap tuc:"
echo "     kernel cua may DNS gui ve ICMP port unreachable vi cong 53 dang dong."
echo "   • curl bao exit 6 'Could not resolve host' — KHAC KB2 (exit 28)."
echo "   • ping toi DNS server VAN THONG. May song, DICH VU chet."
echo "     Neu monitoring cua ban chi ping may DNS thi no dang bao mau xanh."
echo ""
echo "⚠️  CHU Y 1: KB3 va KB4 cho curl CUNG MOT cau 'Could not resolve host' (exit 6)"
echo "    trong khi nguyen nhan khac han nhau. curl KHONG du de chan doan — phai dig."
echo ""
echo "⚠️  CHU Y 2 (bay thuc dia): neu ban ban dig LIEN TUC nhieu lan trong 1 giay,"
echo "    ban se thay 'connection refused' thinh thoang doi thanh 'timed out'."
echo "    Do KHONG phai benh doi — do la net.ipv4.icmp_ratelimit cua Linux, mac dinh"
echo "    chi cho phat 1 goi ICMP unreachable moi giay. Goi thu 2 tro di bi kernel nuot,"
echo "    va 'tu choi' trong giong het 'im lang'."
echo "    -> Khi chan doan, dig THONG THA tung lan mot. Ban lien tuc la tu lam nhieu"
echo "       chinh bang chung cua minh."
