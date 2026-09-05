#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 9 — PREEMPT: MỘT SỰ CỐ, HAI LẦN MẤT PHIÊN
#
# Mặc định Keepalived bật preempt: node priority cao hơn LUÔN giành lại VIP ngay
# khi nó sống lại. Một lần node-a chết vì thế sinh ra HAI lần chuyển VIP:
#   lần 1: node-a chết     -> VIP sang node-b   (bắt buộc)
#   lần 2: node-a sống lại -> VIP về node-a     (HOÀN TOÀN KHÔNG CẦN THIẾT)
#
# ⚠️ ĐO BẰNG PING SẼ KHÔNG THẤY GÌ. Lần chuyển thứ 2 diễn ra "êm": node-a báo
#    priority cao hơn, node-b nhường, GARP bắn ngay -> mất chưa tới 0.4 giây,
#    ping hầu như không rớt gói. Nhưng cái GIÁ THẬT nằm ở tầng trên:
#    MỌI PHIÊN TCP đang mở lại đứt thêm một lần nữa (xem kịch bản 2).
#
# Vì vậy kịch bản này đo bằng KẾT NỐI ĐANG MỞ, không đo bằng ping.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

tai_file() {   # $1 = tên kết quả
    docker exec -d $CLIENT_REMOTE sh -c "
      rm -f /tmp/$1
      curl -s --max-time 40 -o /dev/null \
           -w 'tai_ve=%{size_download}/2097152 bytes  thoi_gian=%{time_total}s' \
           http://$VIP/big.bin > /tmp/$1 2>&1
      echo \" curl_exit=\$?\" >> /tmp/$1
    "
}
# Chờ tới khi curl kết thúc hẳn rồi mới đọc kết quả.
# Nếu VIP bị giành lại, kết nối cũ không bị RST mà bị RƠI IM LẶNG (gói đi tới
# node mới, node đó không biết phiên này nên bỏ qua) -> curl treo tới hết
# --max-time. Đọc sớm sẽ ra chuỗi rỗng và người xem tưởng script hỏng.
ket_qua() {
    for _ in $(seq 45); do
        R=$(docker exec $CLIENT_REMOTE sh -c "cat /tmp/$1 2>/dev/null")
        case "$R" in *curl_exit=*) echo "$R"; return ;; esac
        sleep 1
    done
    echo "(vẫn đang treo sau 45s — kết nối rơi im lặng, không hề có RST)"
}

chay_kich_ban() {
    # Chốt chặn: phải thực sự phục vụ được 200 OK rồi mới bắt đầu đo. Không có
    # bước này thì kết nối #1 có thể mở đúng lúc HAProxy chưa nhận đủ backend,
    # kết quả ra 503 vài trăm byte và cả kịch bản mất ý nghĩa.
    if ! wait_vip_up 45; then
        echo "   ❌ VIP chưa phục vụ được, dừng lại. Chạy ./scripts/0-setup.sh."
        return 1
    fi
    echo "   ⬇️  Mở kết nối #1 (tải file 2MB, ~20s)..."
    tai_file dl1.txt
    sleep 5

    echo "   💥 SIGKILL node-a  -> sự cố THẬT"
    docker compose kill node-a >/dev/null 2>&1
    sleep 14
    echo "      VIP giờ ở: $(vip_owner)"

    echo "   ⬇️  Mở kết nối #2 trên node đang phục vụ (đang chạy hoàn toàn tốt)..."
    tai_file dl2.txt
    sleep 5

    echo "   🔌 node-a SỐNG LẠI"
    docker compose start node-a >/dev/null 2>&1
    # Container restart -> route tĩnh bay sạch. Không cài lại thì HAProxy của
    # node-a không với tới backend ở tầng .53 và sẽ trả 503 thay vì phục vụ.
    sleep 3
    cai_route $NODE_A
    sleep 27
    echo "      VIP giờ ở: $(vip_owner)"

    echo ""
    echo "   Kết nối #1 (lúc node-a chết) : $(ket_qua dl1.txt)"
    echo "   Kết nối #2 (lúc node-a về)   : $(ket_qua dl2.txt)"
}

# ==============================================================================
echo "################################################################"
echo "# PHẦN 1 — MẶC ĐỊNH (preempt bật)"
echo "################################################################"
echo "📋 VIP đang nằm trên: $(vip_owner)"
chay_kich_ban
echo ""
echo "👉 CẢ HAI kết nối đều đứt. Kết nối #2 đứt chỉ vì node-a hồi phục và"
echo "   đòi lại VIP — trong khi node-b đang phục vụ hoàn hảo."

# ==============================================================================
echo ""
echo "################################################################"
echo "# PHẦN 2 — BẬT nopreempt"
echo "################################################################"
echo "🔧 Đặt cờ nopreempt trên cả 2 node rồi nạp lại Keepalived..."
echo "   - nopreempt CHỈ hợp lệ khi state = BACKUP. Đặt state MASTER kèm"
echo "     nopreempt thì keepalived báo lỗi và bỏ qua."
echo "   - Cờ ghi ra file để SỐNG SÓT qua lần restart container ở dưới."

for N in $NODE_A $NODE_B; do
    docker exec "$N" touch /etc/keepalived/USE_NOPREEMPT
    docker exec "$N" pkill -9 keepalived 2>/dev/null || true
    docker exec "$N" ip addr del $VIP/24 dev eth0 2>/dev/null || true
done
sleep 1
docker exec $NODE_A ka-start /etc/keepalived/keepalived-nopreempt.conf
sleep 4
docker exec $NODE_B ka-start /etc/keepalived/keepalived-nopreempt.conf
sleep 6
echo "   VIP đang nằm trên: $(vip_owner)"
echo ""
chay_kich_ban
echo ""
echo "👉 Kết nối #1 vẫn đứt (sự cố thật, không tránh được)."
echo "   Kết nối #2 SỐNG SÓT — node-a hồi phục nhưng KHÔNG đòi lại VIP."

echo ""
echo "=========================================="
echo "🔑 ĐÚC KẾT"
echo "=========================================="
echo "   preempt (mặc định): 2 lần mất phiên — 1 do sự cố, 1 do tự gây ra."
echo "   nopreempt         : 1 lần mất phiên — đúng bằng sự cố thật."
echo ""
echo "   ⚠️ Đây là lý do đo HA bằng ping là chưa đủ: lần chuyển thứ hai gần như"
echo "      không rớt gói ICMP nào, nhưng vẫn giết sạch session đang mở."
echo ""
echo "   Khi nào dùng preempt?   Khi hai node KHÔNG ngang nhau (node chính mạnh"
echo "                           hơn hẳn, node phụ chỉ gánh tạm)."
echo "   Khi nào dùng nopreempt? Khi hai node NGANG NHAU — đa số trường hợp."
echo "                           Đã chạy tốt trên node-b thì không có lý do gì"
echo "                           phải chuyển ngược lại."
echo "   Ở giữa: preempt_delay <giây> — chờ node vừa hồi phục ổn định rồi mới"
echo "           giành lại, tránh flapping liên tục."
echo ""
echo "⚠️  nopreempt vẫn đang bật. Chạy ./scripts/0-setup.sh để trả về mặc định."
