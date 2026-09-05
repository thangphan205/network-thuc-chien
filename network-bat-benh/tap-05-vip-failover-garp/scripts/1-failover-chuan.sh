#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 1 — FAILOVER ĐÚNG CHUẨN (mốc so sánh cho toàn tập)
#
# Giết MASTER bằng SIGKILL (máy chết đột ngột, không kịp bàn giao) rồi đo
# downtime ở CẢ HAI client: client-lan (cùng subnet VIP) và client-remote
# (khác subnet, đi qua router). Keepalived tự phát GARP nên cả hai phải hồi
# phục gần như cùng lúc — đó là ý nghĩa của mốc này.
#
# ⚠️ Vì sao đếm icmp_seq mà không dùng `date +%s%N`?
#    Client chạy busybox trên Alpine, `date` ở đó KHÔNG hỗ trợ %N (nano giây).
#    Đếm số icmp_seq bị thiếu rồi nhân với chu kỳ ping cho kết quả ổn định hơn.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

# Đo downtime từ log ping: tìm khoảng trống lớn nhất giữa 2 icmp_seq liên tiếp.
do_downtime() {
    local LOG="$1"
    local SEQS
    SEQS=$(docker exec "$2" grep -o 'icmp_seq=[0-9]*' "$LOG" 2>/dev/null | cut -d= -f2)
    [ -z "$SEQS" ] && { echo "(khong co du lieu)"; return; }
    echo "$SEQS" | awk '
        NR==1 { prev=$1; max=0; next }
        { d=$1-prev-1; if (d>max) max=d; prev=$1 }
        END { printf "%.1f giây (mất %d gói liên tiếp)", max*0.2, max }'
}

echo "=========================================="
echo "🩺 [MỐC] Trạng thái trước khi giết MASTER"
echo "=========================================="
echo "VIP $VIP đang nằm trên: $(vip_owner)"
echo "MAC thật: node-a=$(mac_of $NODE_A)  node-b=$(mac_of $NODE_B)"
in_bang_arp

echo ""
echo "⏳ Bật ping liên tục (0.2s/gói) từ CẢ HAI client..."
docker exec -d $CLIENT_LAN    sh -c "ping -i 0.2 -W 1 $VIP > /tmp/ping.log 2>&1"
docker exec -d $CLIENT_REMOTE sh -c "ping -i 0.2 -W 1 $VIP > /tmp/ping.log 2>&1"
sleep 3

echo "💥 SIGKILL node-a (MASTER) — chết đột ngột, không kịp nhường quyền..."
docker compose kill node-a >/dev/null 2>&1

echo "⏳ Chờ 15 giây cho VRRP hội tụ và GARP lan ra..."
sleep 15

docker exec $CLIENT_LAN    pkill ping 2>/dev/null || true
docker exec $CLIENT_REMOTE pkill ping 2>/dev/null || true

echo ""
echo "=========================================="
echo "📊 KẾT QUẢ ĐO"
echo "=========================================="
echo "VIP giờ nằm trên: $(vip_owner)"
printf "   %-16s DOWNTIME ≈ %s\n" "client-lan:"    "$(do_downtime /tmp/ping.log $CLIENT_LAN)"
printf "   %-16s DOWNTIME ≈ %s\n" "client-remote:" "$(do_downtime /tmp/ping.log $CLIENT_REMOTE)"
echo ""
echo "Bảng ARP sau failover (Keepalived đã tự bắn GARP):"
in_bang_arp

echo ""
echo "🔑 ĐỌC KẾT QUẢ:"
echo "   - Con số ~3 giây ≈ 3 × advert_int. Đó là thời gian VRRP CẦN để chắc"
echo "     chắn MASTER đã chết, KHÔNG phải thời gian cập nhật ARP."
echo "   - Hai client hồi phục gần như cùng lúc vì GARP là broadcast: router"
echo "     có chân trong LAN của VIP nên nó nhận được y hệt client-lan."
echo "   - Đây là mốc ĐÚNG. Các kịch bản sau sẽ phá từng mảnh của mốc này."
echo ""
echo "👉 Tiếp theo: ./scripts/2-dut-phien-tcp.sh   (rồi ./scripts/0-setup.sh để reset)"
