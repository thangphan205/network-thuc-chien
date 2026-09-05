#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 6 — CHỮA CHÁY TỪ PHÍA ROUTER (khi bạn không với được tới server)
#
# 3 giờ sáng. Dịch vụ chết. Bạn chưa biết vì sao node-b không bắn GARP, và
# team server chưa ai bốc máy. Nhưng bạn có quyền vào router.
#
# Xoá đúng MỘT dòng trong bảng ARP của router là dịch vụ sống lại ngay.
# Dòng lệnh tương đương trên thiết bị thật:
#     Cisco IOS : clear arp-cache  /  clear ip arp 172.28.52.100
#     NX-OS     : clear ip arp 172.28.52.100 vrf all
#     Juniper   : clear arp hostname 172.28.52.100
#
# Kịch bản này còn chứng minh một điều quan trọng: chỉ router được chữa, còn
# client-lan (cùng subnet với VIP) VẪN CHẾT — vì không ai chữa cho nó.
# Đó là bằng chứng rõ nhất rằng hai máy này ốm ĐỘC LẬP với nhau.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

LB_IF=$(r_lb_if)

echo "🚨 Dựng lại ca bệnh (script tự chế cướp VIP, không GARP)..."
hoi_phuc_ha
# Bật ARP kiểu Cisco để bệnh KHÔNG tự khỏi giữa chừng làm hỏng phép đo.
set_arp_cisco
docker exec $ROUTER ip neigh flush dev "$LB_IF"
docker exec $CLIENT_REMOTE curl -s --max-time 3 -o /dev/null "http://$VIP/" || true
gay_benh_stale_arp
trap 'echo ""; echo "🧹 Trả router về ARP mặc định Linux..."; set_arp_linux' EXIT

echo ""
echo "📋 TRƯỚC KHI CHỮA:"
in_bang_arp
for C in $CLIENT_REMOTE $CLIENT_LAN; do
    docker exec "$C" curl -sf --max-time 3 -o /dev/null "http://$VIP/" 2>/dev/null \
        && printf "   %-24s SỐNG\n" "$C" \
        || printf "   %-24s CHẾT\n" "$C"
done

echo ""
echo "💊 CHỮA CHÁY — xoá đúng một dòng ARP trên router:"
echo "        docker exec $ROUTER ip neigh del $VIP dev $LB_IF"
docker exec $ROUTER ip neigh del "$VIP" dev "$LB_IF"
sleep 2
# Gọi một phát cho router ARP hỏi lại và học MAC đúng.
docker exec $CLIENT_REMOTE curl -s --max-time 3 -o /dev/null "http://$VIP/" || true
sleep 1

echo ""
echo "📋 SAU KHI CHỮA:"
in_bang_arp
for C in $CLIENT_REMOTE $CLIENT_LAN; do
    docker exec "$C" curl -sf --max-time 3 -o /dev/null "http://$VIP/" 2>/dev/null \
        && printf "   %-24s SỐNG  ✅\n" "$C" \
        || printf "   %-24s CHẾT  ❌ (chưa ai chữa cho máy này)\n" "$C"
done

echo ""
echo "=========================================="
echo "🔑 ĐỌC KẾT QUẢ — ba điều rút ra"
echo "=========================================="
echo "   1. client-remote sống lại NGAY, mà không ai đụng vào nó. Chứng minh"
echo "      ổ bệnh nằm ở router, đúng một dòng, không phải ở client."
echo ""
echo "   2. client-lan VẪN CHẾT. Nó ở cùng subnet với VIP nên nó có bảng ARP"
echo "      RIÊNG, cũng sai, và việc chữa router không giúp gì cho nó. Mỗi"
echo "      thiết bị trong broadcast domain ốm độc lập — đó là lý do cách chữa"
echo "      ĐÚNG (kịch bản 4) phải là GARP broadcast, chữa tất cả cùng lúc."
echo ""
echo "   3. Đây là CHỮA CHÁY, không phải chữa bệnh:"
echo "      - Lần failover sau lại chết y hệt."
echo "      - Trên router lớn, 'clear arp-cache' toàn cục làm rớt hết neighbor"
echo "        của mọi VLAN cùng lúc — đừng gõ lệnh đó giờ cao điểm. Xoá đúng"
echo "        một IP thôi."
echo "      - Và thường sysadmin KHÔNG có quyền vào router. Trong sự cố thật,"
echo "        bước này phải chờ team mạng — thêm 20 phút downtime."
echo ""
echo "👉 Vì sao bắn thêm GARP không cứu được client remote? ./scripts/7-garp-khong-xuyen-router.sh"
echo "👉 Reset: ./scripts/0-setup.sh"
