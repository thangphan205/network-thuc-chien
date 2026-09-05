#!/usr/bin/env bash
# ==============================================================================
# BẮT GÓI ARP — chạy ở terminal riêng rồi kích hoạt failover ở terminal khác.
#
#   ./scripts/bat-goi-garp.sh            # bắt ở chân LB LAN của router (mặc định)
#   ./scripts/bat-goi-garp.sh client     # bắt ở client-lan (cùng subnet VIP)
#   ./scripts/bat-goi-garp.sh remote     # bắt ở client-remote (bên kia router)
#
# ⚠️ Vì sao mặc định bắt ở ROUTER chứ không phải ở client?
#    Vì trong topology có định tuyến, ROUTER mới là thiết bị nghe được GARP.
#    Bắt ở client-remote thì bạn sẽ ngồi nhìn màn hình trống — và đó chính là
#    bài học của kịch bản 7.
#
#    Cũng đừng bắt trên chính node vừa failover: ở đó lúc nào cũng thấy gói đi
#    ra, nên không chứng minh được gì. Phải bắt ở MÁY THỨ BA.
# ==============================================================================
cd "$(dirname "$0")/.."
source scripts/lib.sh

case "${1:-router}" in
    client) CT=$CLIENT_LAN    ; IF=eth0        ; MOTA="client-lan (cùng subnet VIP)" ;;
    remote) CT=$CLIENT_REMOTE ; IF=eth0        ; MOTA="client-remote (bên kia router — sẽ KHÔNG thấy gì)" ;;
    router) CT=$ROUTER        ; IF=$(r_lb_if)  ; MOTA="router chân LB LAN (nơi GARP thực sự tới)" ;;
    *) echo "Dùng: $0 [router|client|remote]"; exit 1 ;;
esac

echo "📡 Đang bắt ARP tại: $MOTA   ($CT / $IF)"
echo ""
echo "Dấu hiệu nhận biết Gratuitous ARP — Sender IP TRÙNG Target IP:"
echo "    Request who-has $VIP tell $VIP"
echo ""
echo "Bộ lọc chặt hơn nếu LAN nhiều nhiễu (bắt cả Request lẫn Reply):"
echo "    tcpdump -i $IF -n -e 'arp[14:4] = arp[24:4]'"
echo ""
echo "⚠️ Đừng thêm 'arp[6:2] = 1' để lọc riêng Request: arping -A phát GARP dạng"
echo "   REPLY (opcode 2), lọc kiểu đó sẽ mất gói rồi kết luận nhầm 'không có GARP'."
echo "   Wireshark có sẵn tương đương: arp.isgratuitous == 1"
echo ""
echo "Giờ mở terminal khác chạy ./scripts/4-fix.sh hoặc ./scripts/1-failover-chuan.sh."
echo "(Ctrl-C để dừng)"
echo ""
docker exec "$CT" tcpdump -i "$IF" -e -n arp
