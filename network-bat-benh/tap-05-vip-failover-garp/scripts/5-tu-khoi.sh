#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 5 — KHÔNG CHỮA GÌ CẢ: BAO LÂU THÌ TỰ KHỎI?
#
# Chạy hai phần để thấy con số "tự khỏi sau 30 giây" phụ thuộc HOÀN TOÀN vào
# thiết bị nào đang ôm bảng ARP sai:
#
#   PHẦN 1 — Router là Linux (có NUD). Linux tự dò lại neighbor khi thấy im
#            lặng -> tự khỏi sau ~30-50 giây.
#   PHẦN 2 — Router là Cisco IOS (ARP timeout 14400s, KHÔNG có NUD). Không có
#            cơ chế nào tự kiểm tra lại -> chết 4 TIẾNG.
#
# Phần 2 giả lập Cisco bằng sysctl neigh trên chân .52 của router.
#
# ⚠️ Đo bằng ĐỒNG HỒ TƯỜNG (date +%s), không đếm vòng lặp: mỗi vòng tốn ~1-2
#    giây cho curl nên đếm vòng lặp sẽ ra số sai.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

# Luôn trả router về Linux mặc định dù script thoát kiểu gì.
trap 'echo ""; echo "🧹 Trả router về ARP mặc định Linux..."; set_arp_linux' EXIT

# Đo thời gian tới khi $1 gọi được VIP, tối đa $2 giây. In ra số giây hoặc "".
do_tu_khoi() {
    local C="$1" MAX="$2" START NOW
    START=$(date +%s)
    while [ $(( $(date +%s) - START )) -lt "$MAX" ]; do
        if docker exec "$C" curl -sf --max-time 1 -o /dev/null "http://$VIP/" 2>/dev/null; then
            echo $(( $(date +%s) - START )); return 0
        fi
        sleep 1
    done
    echo ""; return 1
}

# ------------------------------------------------------------------------------
echo "=============================================================="
echo "PHẦN 1 — ROUTER LINUX (có NUD): bệnh tự khỏi"
echo "=============================================================="
hoi_phuc_ha
set_arp_linux
echo "🚨 Gây bệnh: node-b cướp VIP không GARP..."
gay_benh_stale_arp
in_bang_arp
echo ""
echo "⏳ Ngồi im, không chữa gì. Đo bằng đồng hồ tường (tối đa 150 giây)..."

T_REMOTE=$(do_tu_khoi $CLIENT_REMOTE 150) || true
T_LAN=$(do_tu_khoi $CLIENT_LAN 10) || true

if [ -n "$T_REMOTE" ]; then
    printf "   %-16s TỰ KHỎI sau ~%s giây\n" "client-remote:" "$T_REMOTE"
else
    printf "   %-16s VẪN CHẾT sau 150 giây\n" "client-remote:"
fi
if [ -n "$T_LAN" ]; then
    printf "   %-16s cũng đã sống (chung một bảng ARP được sửa)\n" "client-lan:"
else
    printf "   %-16s vẫn chết\n" "client-lan:"
fi
echo ""
echo "   Bảng ARP sau khi tự khỏi:"
in_bang_arp
echo ""
echo "   👉 Linux có NUD (Neighbour Unreachability Detection): thấy entry im"
echo "      lặng quá lâu thì nó tự gửi ARP probe hỏi lại. Không ai chữa, nó tự"
echo "      chữa. ĐÂY LÀ MAY MẮN, KHÔNG PHẢI THIẾT KẾ."

# ------------------------------------------------------------------------------
echo ""
echo "=============================================================="
echo "PHẦN 2 — ROUTER CISCO (ARP timeout 4 tiếng): bệnh KHÔNG tự khỏi"
echo "=============================================================="
hoi_phuc_ha
echo "🔧 Giả lập ARP timeout kiểu Cisco IOS trên chân $(r_lb_if) của router:"
echo "     base_reachable_time_ms = 14400000   (4 tiếng)"
echo "     gc_stale_time          = 14400"
echo "     delay_first_probe_time = 14400"
set_arp_cisco
# base_reachable_time_ms chỉ áp cho entry HỌC MỚI -> phải xoá entry cũ rồi học lại.
docker exec $ROUTER ip neigh flush dev "$(r_lb_if)"
docker exec $CLIENT_REMOTE curl -s --max-time 3 -o /dev/null "http://$VIP/" || true
echo "   Entry mới của router: $(docker exec $ROUTER ip neigh show $VIP dev "$(r_lb_if)")"

echo ""
echo "🚨 Gây lại đúng ca bệnh đó..."
gay_benh_stale_arp
in_bang_arp
echo ""
echo "⏳ Ngồi im 90 giây (phần 1 chỉ cần ~30-50 giây là khỏi)..."
T2=$(do_tu_khoi $CLIENT_REMOTE 90) || true

if [ -n "$T2" ]; then
    echo "   ⚠️  Tự khỏi sau $T2 giây — sysctl chưa ăn. Kiểm tra lại chân router."
else
    echo "   ❌ VẪN CHẾT sau 90 giây."
    echo "   Trạng thái entry ARP của router:"
    docker exec $ROUTER ip neigh show "$VIP" dev "$(r_lb_if)" | sed 's/^/      /'
    echo "      ↑ Vẫn REACHABLE với MAC của máy đã chết. Router TIN chắc entry này"
    echo "        còn tốt và sẽ không kiểm tra lại trong 4 tiếng tới."
fi

echo ""
echo "=============================================================="
echo "🔑 BẢNG ARP TIMEOUT MẶC ĐỊNH — vì sao phải biết số này"
echo "=============================================================="
cat <<'TBL'
   Thiết bị              ARP timeout      Có NUD?   Tự khỏi?
   --------------------- ---------------- --------- ----------------------
   Linux (host/router)   ~30-60 giây      CÓ        ~30-50 giây
   Juniper JunOS         1200 giây (20p)  KHÔNG     20 phút
   Cisco NX-OS           1500 giây (25p)  KHÔNG     25 phút
   Cisco IOS / IOS-XE    14400 giây (4h)  KHÔNG     4 TIẾNG
TBL
echo ""
echo "   Bạn test lab trên Linux thấy 'tự khỏi sau 30 giây' rồi yên tâm."
echo "   Production chạy Cisco IOS: cùng sự cố đó = 4 tiếng downtime."
echo "   Tệ hơn nữa, với CEF adjacency thì gói bị drop im lặng, không sinh log."
echo ""
echo "👉 Chữa cháy từ phía router: ./scripts/6-chua-tren-router.sh"
echo "👉 Reset:                    ./scripts/0-setup.sh"
