#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 4 — CHỮA: BA (NĂM) GÓI ARP, BẮN TỪ PHÍA SERVER
#
# Điểm mấu chốt: KHÔNG đụng gì vào client, KHÔNG đụng gì vào router.
# Node đang giữ VIP tự đứng ra "khai báo hộ khẩu": tôi là chủ mới của IP này,
# MAC của tôi đây. Cả broadcast domain nghe thấy và cập nhật — router nằm
# trong domain đó nên nó cập nhật theo.
#
# ⚠️ Vì sao -c 5 mà không phải -c 3?
#    GARP là broadcast: không ACK, không retransmit. Mất là mất luôn. Khi có
#    router/switch doanh nghiệp ở giữa (buffer đầy, storm-control, DAI) thì 3
#    gói là mỏng. Bắn 5 gói tốn thêm vài mili-giây, đổi lại đỡ phải giải thích
#    với sếp vì sao dịch vụ chết thêm 4 tiếng.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

OWNER=$(vip_owner)
case "$OWNER" in
    node-a) TARGET=$NODE_A ;;
    node-b) TARGET=$NODE_B ;;
    *) echo "❌ Không node nào đang giữ VIP $VIP. Chạy ./scripts/3-fault.sh trước."; exit 1 ;;
esac

echo "📋 TRƯỚC KHI CHỮA — hai bảng ARP đang trỏ về máy đã chết:"
in_bang_arp

echo ""
echo "💊 CHỮA — bắn Gratuitous ARP từ $OWNER (máy đang thực sự giữ VIP):"
echo "        docker exec $TARGET arping -U -c 5 -I eth0 $VIP"
docker exec $TARGET arping -U -c 5 -I eth0 "$VIP" 2>&1 | sed 's/^/   /'
sleep 2

echo ""
echo "📋 SAU KHI CHỮA — không hề đụng vào client hay router:"
in_bang_arp

echo ""
echo "=========================================="
echo "🩺 Dịch vụ sống lại chưa?"
echo "=========================================="
for C in $CLIENT_LAN $CLIENT_REMOTE; do
    OUT=$(docker exec "$C" curl -s --max-time 4 -i "http://$VIP/" 2>/dev/null) && RC=0 || RC=$?
    if [ "$RC" = "0" ]; then
        printf "   ✅ %-24s %s\n" "$C" "$(echo "$OUT" | grep -i '^HTTP/' | tr -d '\r')"
        echo "$OUT" | grep -iE '^x-lb-node|^x-web-server' | tr -d '\r' | sed 's/^/      /'
    else
        printf "   ❌ %-24s curl_exit=%s\n" "$C" "$RC"
    fi
done

echo ""
echo "=========================================="
echo "🔑 ĐỌC KẾT QUẢ"
echo "=========================================="
echo "   - Bạn KHÔNG chạm vào client. Bạn KHÔNG chạm vào router."
echo "   - Một lệnh chạy trên SERVER sửa được bảng ARP của một thiết bị khác."
echo "     Đó chính là toàn bộ ý nghĩa của Gratuitous ARP."
echo ""
echo "   ⚠️ Nhưng đây vẫn là CHỮA TRIỆU CHỨNG. Lần failover sau, script tự chế"
echo "      lại quên GARP lần nữa. Chữa gốc = vứt script đi, dùng Keepalived"
echo "      (nó tự bắn GARP, không tắt được), hoặc dùng use_vmac — xem kịch bản 12."
echo ""
echo "   Ngoài đời, dòng lệnh này nằm ở đâu?"
echo "     - keepalived : tự động, không cần khai báo (hoặc notify_master)"
echo "     - pacemaker  : ocf:heartbeat:IPaddr2 có tham số arp_count / arp_bg"
echo "     - script tự chế: PHẢI tự thêm arping -U ngay sau ip addr add"
echo ""
echo "👉 Reset: ./scripts/0-setup.sh"
