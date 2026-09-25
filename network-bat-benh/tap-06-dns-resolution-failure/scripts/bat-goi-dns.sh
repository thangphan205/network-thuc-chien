#!/usr/bin/env bash
# ==============================================================================
# BAT GOI TIN DNS trong container client roi ghi ra file .pcap de mo bang Wireshark.
#
#   ./scripts/bat-goi-dns.sh [so_giay] [ten_mien]
#
# Bat TRONG container chu khong bat tren card mang cua may that: goi tin DNS cua
# lab khong bao gio ra khoi bridge, tren macOS/Windows ban khong soi duoc bang
# Wireshark cai san. Bat trong container thi chay giong nhau tren moi he dieu hanh.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

GIAY=${1:-12}
TEN_HOI=${2:-$TEN}
FILE="dns-$(date +%H%M%S).pcap"

echo "🦈 Bat goi tin UDP/TCP cong 53 trong $CLIENT trong $GIAY giay..."
docker exec -d $CLIENT sh -c "tcpdump -i eth0 -w /tmp/cap.pcap 'port 53' 2>/dev/null"
sleep 1

echo "   Dang sinh luu luong: dig $TEN_HOI + curl http://$TEN_HOI/"
docker exec $CLIENT dig "$TEN_HOI" >/dev/null 2>&1 || true
docker exec $CLIENT curl -s -o /dev/null --connect-timeout 3 --max-time 5 "http://$TEN_HOI/" >/dev/null 2>&1 || true

sleep "$GIAY"
docker exec $CLIENT pkill -x tcpdump 2>/dev/null || true
sleep 1
docker cp "$CLIENT:/tmp/cap.pcap" "./$FILE" >/dev/null

echo ""
echo "✅ Da luu: $(pwd)/$FILE"
echo "   So goi: $(docker exec $CLIENT sh -c 'tcpdump -r /tmp/cap.pcap 2>/dev/null | wc -l' | tr -d ' ')"
echo ""
echo "👉 Mo bang Wireshark, dat display filter:  dns"
echo "   • Chi thay 'Standard query', khong thay 'query response' -> khong ai tra loi (KB2/KB5)."
echo "   • Thay 'query response ... No such name'                 -> NXDOMAIN (KB4)."
echo "   • Thay 'query response A $IP_WEB_CU'                     -> co tra loi, nhung SAI IP (KB6)."
echo "   • KHONG thay goi nao ca                                  -> ung dung khong he hoi DNS"
echo "                                                               (/etc/hosts hoac cache — KB7/KB8)."
