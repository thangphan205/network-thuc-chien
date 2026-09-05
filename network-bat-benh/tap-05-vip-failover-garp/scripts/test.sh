#!/usr/bin/env bash
# ==============================================================================
# CHẨN ĐOÁN: đi từ ngoài vào trong, xác định ổ bệnh nằm ở tầng nào.
#
# Thứ tự 8 bước không phải ngẫu nhiên — nó là đúng quy trình bạn nên làm ngoài
# đời khi nhận được câu than "HA failover xong rồi mà dịch vụ vẫn chết".
# ==============================================================================
cd "$(dirname "$0")/.."
source scripts/lib.sh

A_MAC=$(mac_of $NODE_A)
B_MAC=$(mac_of $NODE_B)
OWNER=$(vip_owner)
LB_IF=$(r_lb_if)

case "$OWNER" in
    node-a) EXPECT_MAC="$A_MAC" ;;
    node-b) EXPECT_MAC="$B_MAC" ;;
    *)      EXPECT_MAC="" ;;
esac

echo "=========================================="
echo "🩺 [BƯỚC 1] MAC THỰC TẾ của 2 node LB:"
echo "=========================================="
echo "node-a (172.28.52.11):  ${A_MAC:-(node-a đang CHẾT — đúng kịch bản failover)}"
echo "node-b (172.28.52.12):  ${B_MAC:-(node-b đang CHẾT)}"
echo "VIP $VIP hiện nằm trên: $OWNER"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] KEEPALIVED còn sống không?"
echo "=========================================="
for N in $NODE_A $NODE_B; do
    # Khớp CHÍNH XÁC tên tiến trình và loại trừ zombie (<defunct>).
    # Không dùng `ps aux | grep keepalived` vì dễ khớp nhầm vào chính câu lệnh.
    if docker exec "$N" sh -c 'for p in $(pgrep -x keepalived 2>/dev/null); do [ "$(awk "{print \$3}" /proc/$p/stat 2>/dev/null)" != "Z" ] && exit 0; done; exit 1' 2>/dev/null; then
        echo "  $N: Keepalived ĐANG CHẠY"
    else
        echo "  $N: Keepalived KHÔNG chạy (hoặc container đã tắt)"
    fi
done

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Bảng ARP của CLIENT CÙNG LAN:"
echo "=========================================="
CLAN_MAC=$(client_lan_vip_mac)
docker exec $CLIENT_LAN ip neigh show
echo ""
if [ -z "$CLAN_MAC" ]; then
    echo "👉 client-lan chưa học MAC nào cho VIP (gọi thử VIP một lần để nó học)."
elif [ -z "$EXPECT_MAC" ]; then
    echo "⚠️  Không node nào đang giữ VIP $VIP."
elif [ "$CLAN_MAC" = "$EXPECT_MAC" ]; then
    echo "✅ client-lan đang trỏ ĐÚNG MAC của $OWNER ($CLAN_MAC)."
else
    echo "❌ client-lan đang ôm MAC $CLAN_MAC trong khi VIP đã sang $OWNER ($EXPECT_MAC)!"
fi

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 4] Bảng ARP của ROUTER (chân $LB_IF) — Ổ BỆNH THẬT:"
echo "=========================================="
RMAC=$(router_vip_mac)
docker exec $ROUTER ip neigh show dev "$LB_IF"
echo ""
if [ -z "$RMAC" ]; then
    echo "👉 Router chưa học MAC cho VIP — nó sẽ ARP hỏi ở gói tiếp theo."
elif [ -z "$EXPECT_MAC" ]; then
    echo "⚠️  Không node nào đang giữ VIP $VIP."
elif [ "$RMAC" = "$EXPECT_MAC" ]; then
    echo "✅ Router đang trỏ ĐÚNG MAC của $OWNER ($RMAC)."
else
    echo "❌ Router đang ôm MAC $RMAC ($(mac_to_node "$RMAC")) trong khi VIP đã sang $OWNER!"
    echo "   Router forward frame tới một máy đã tắt thở -> BLACKHOLE cho TOÀN BỘ"
    echo "   client ở các subnet khác. Không sửa gì ở client cứu được ca này."
fi

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 5] Bảng ARP của CLIENT REMOTE — vì sao soi ở đây là ngõ cụt:"
echo "=========================================="
docker exec $CLIENT_REMOTE ip neigh show
if docker exec $CLIENT_REMOTE ip neigh show 2>/dev/null | grep -q "^$VIP "; then
    echo "⚠️  Bất thường: client-remote có entry cho VIP — kiểm tra lại route."
else
    echo "👉 KHÔNG có dòng nào cho $VIP — và đó là ĐÚNG."
    echo "   client-remote khác subnet nên nó chỉ ARP hỏi gateway $R_CLIENT."
    echo "   Bảng ARP của nó LUÔN SẠCH kể cả khi dịch vụ chết hoàn toàn."
fi

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 6] Gọi dịch vụ thật qua VIP từ CẢ HAI client:"
echo "=========================================="
BLACKHOLE=0
for C in $CLIENT_LAN $CLIENT_REMOTE; do
    OUT=$(docker exec "$C" curl -s -o /dev/null --max-time 4 \
              -w '%{http_code}' "http://$VIP/" 2>/dev/null)
    RC=$?
    case "$OUT/$RC" in
        200/0) echo "  ✅ $C: HTTP 200" ;;
        503/0) echo "  🟡 $C: HTTP 503 — CÓ response! HAProxy sống nhưng mất backend."
               echo "     -> Lỗi ở Tầng 3/7, KHÔNG phải bảng ARP. Xem cảnh 11." ;;
        */28)  echo "  ❌ $C: curl (28) TIMEOUT — không có response nào."
               echo "     -> Chữ ký của blackhole Tầng 2: frame gửi vào hư vô."
               BLACKHOLE=1 ;;
        */7)   echo "  ❌ $C: curl (7) CONNECTION REFUSED — gói ĐẾN được đích và bị từ chối."
               echo "     -> Đích sống nhưng không ai nghe cổng 80. Không phải ca bệnh ARP." ;;
        *)     echo "  ❌ $C: http_code=$OUT curl_exit=$RC" ;;
    esac
done

if [ "$BLACKHOLE" = "1" ]; then
    echo ""
    echo "  🔎 traceroute từ client-remote (xem gói chết ở hop nào):"
    docker exec $CLIENT_REMOTE traceroute -n -w 1 -m 4 "$VIP" 2>&1 | sed 's/^/     /'
    echo "     👉 Chết NGAY SAU hop router = biên L3 cuối cùng còn sống."
fi

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 7] CHIỀU NGƯỢC có thông không? (chữ ký 'lỗi một chiều')"
echo "=========================================="
SRC=$NODE_B ; [ "$OWNER" = "node-a" ] && SRC=$NODE_A
if docker exec "$SRC" ping -c 2 -W 1 "$IP_CLIENT_REMOTE" >/dev/null 2>&1; then
    echo "  ✅ $SRC -> client-remote: THÔNG."
    echo "     Chiều đi chết mà chiều về sống là chữ ký kinh điển của stale ARP:"
    echo "     node biết đường ra (ARP gateway của nó vẫn đúng), chỉ có router là"
    echo "     đang ôm MAC sai theo chiều ngược lại."
else
    echo "  ❌ $SRC -> client-remote: KHÔNG thông. Vấn đề rộng hơn bảng ARP —"
    echo "     kiểm tra route tĩnh và ip_forward trên router."
fi

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 8] HAProxy thấy backend thế nào? (backend nằm sau router)"
echo "=========================================="
for N in $NODE_A $NODE_B; do
    echo "--- $N ---"
    docker exec "$N" curl -s --max-time 2 "http://127.0.0.1:8404/;csv" 2>/dev/null \
        | awk -F, 'NR>1 && $2!="" {printf "  %-8s %-8s %s\n", $1, $2, $18}' \
        || echo "  (không lấy được stats — container đang tắt?)"
done
echo ""
echo "👉 Backend báo UP mà client vẫn chết = monitoring của bạn đang BỊ MÙ."
echo "   HAProxy chỉ nhìn xuống dưới, nó không biết gì về bảng ARP phía trên."
