#!/usr/bin/env bash
# ==============================================================================
# MR2 — UDP: timeout NGAN HON TCP RAT NHIEU, nhung "het han" khong giong TCP
#
# UDP khong co bat tay 3 buoc, khong co khai niem SYN/INVALID nhu TCP. Mac
# dinh kernel: nf_conntrack_udp_timeout = 30s (so voi TCP established 432000s
# -- ngan hon 14.400 LAN). Nhung khi mot goi UDP toi ma khong khop entry nao,
# no KHONG bi coi la INVALID -- no don gian duoc coi la mot phien NEW, va neu
# luat FORWARD da cho phep NEW toi cong do thi no VAN DUOC CHUYEN TIEP.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

buoc "MR2 — UDP conntrack timeout ep xuong 5s (mac dinh 30s), idle 7s (vuot)"
dat_tcp_timeout 432000
dat_loose 0
dat_udp_timeout 5

echo "  Bat goi tren server (terminal an, chi de doi chieu cong nguon)..."
docker exec -d $SERVER sh -c "timeout 15 tcpdump -i any -n udp port 9 -w /tmp/udp9.pcap >/dev/null 2>&1"
sleep 1

echo "  Goi 'goi1' -> idle 7s (vuot timeout 5s, entry UDP bi xoa) -> goi 'goi2':"
B=$(hai_goi_udp_qua_idle 7)
echo "  👉 Tong so byte echo nhan duoc: ${B} (8 = ca hai goi qua; 4 = chi goi dau; 0 = khong goi nao)"
sleep 1
echo ""
echo "  Cong NGUON (sau MASQUERADE) cua tung goi, nhin tu SERVER:"
docker exec $SERVER sh -c "tcpdump -r /tmp/udp9.pcap -n 2>/dev/null | grep '> 172.28.17.10.9'" | sed 's/^/     /' || true
echo "👉 Doc chu ky:"
echo "   • UDP timeout mac dinh CHI 30s (TCP la 432000s = ngan hon 14.400 lan)"
echo "     nhung ket qua o day van la ${B} byte — tuc la goi2 VAN QUA duoc du"
echo "     entry cu da bi xoa that (kiem tra bang scripts/xem-conntrack.sh)."
echo "   • Ly do: UDP khong co trang thai 'INVALID vi khong phai SYN' nhu TCP."
echo "     Goi khong khop entry nao -> duoc coi la NEW -> luat FORWARD cho phep"
echo "     NEW toi cong 9 -> VAN DUOC CHUYEN TIEP, tao mot entry MOI."
echo "   • Gateway thuong GIU NGUYEN cong dich da MASQUERADE truoc do (neu con"
echo "     trong) -> ung dung KHONG HE THAY GI KHAC BIET. Day la ly do vi sao"
echo "     nhieu ky su tin 'UDP on dinh hon TCP qua NAT' — thuc ra ca hai deu"
echo "     bi xoa entry, chi khac o cach GATEWAY XU LY goi tiep theo."
echo "   • ⚠️ Nguy hiem thuc su khong nam o day: neu MOT CLIENT KHAC chiem mat"
echo "     dung cong ben ngoai do trong luc entry cu dang trong (nhieu client"
echo "     dong thoi qua cung mot NAT that), goi tra ve co the bi GIAO NHAM"
echo "     cho client khac — loi cross-talk cuc kho tai hien trong lab 1 client."
