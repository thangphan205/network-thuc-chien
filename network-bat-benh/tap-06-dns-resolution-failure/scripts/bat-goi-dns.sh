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

echo "🦈 Bắt gói tin UDP/TCP cổng 53 trong $CLIENT trong $GIAY giây..."
docker exec -d $CLIENT sh -c "tcpdump -i eth0 -w /tmp/cap.pcap 'port 53' 2>/dev/null"
sleep 1

echo "   Đang sinh lưu lượng: dig $TEN_HOI + curl http://$TEN_HOI/"
docker exec $CLIENT dig "$TEN_HOI" >/dev/null 2>&1 || true
docker exec $CLIENT curl -s -o /dev/null --connect-timeout 3 --max-time 5 "http://$TEN_HOI/" >/dev/null 2>&1 || true

sleep "$GIAY"
docker exec $CLIENT pkill -x tcpdump 2>/dev/null || true
sleep 1
docker cp "$CLIENT:/tmp/cap.pcap" "./$FILE" >/dev/null

echo ""
echo "✅ Đã lưu: $(pwd)/$FILE"
echo "   Số gói: $(docker exec $CLIENT sh -c 'tcpdump -r /tmp/cap.pcap 2>/dev/null | wc -l' | tr -d ' ')"
echo ""
echo "👉 Mở bằng Wireshark, đặt display filter:  dns"
echo "   • Chỉ thấy 'Standard query', không thấy 'query response' -> không ai trả lời (KB2/MR3)."
echo "   • Thấy 'query response ... No such name'                 -> NXDOMAIN (MR2)."
echo "   • Thấy 'query response A $IP_WEB_CU'                     -> có trả lời, nhưng SAI IP (MR4)."
echo "   • KHÔNG thấy gói nào cả                                  -> ứng dụng không hề hỏi DNS"
echo "                                                               (/etc/hosts hoặc cache — KB3/MR5)."
