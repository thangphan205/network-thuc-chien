#!/usr/bin/env bash
# ==============================================================================
# KIỂM TRA SỨC KHOẺ VIP — hai cảnh báo mà monitoring thông thường KHÔNG bắt được
#
# Bài học lớn nhất của tập này: HAProxy stats báo XANH HẾT trong khi dịch vụ
# chết. Vì HAProxy chỉ nhìn XUỐNG backend, nó không biết gì về bảng ARP ở phía
# TRÊN nó. Ping VIP từ chính node cũng vô nghĩa — node tự trả lời chính mình.
#
# Script này kiểm 2 thứ mà không công cụ mặc định nào kiểm:
#
#   [1] SPLIT-BRAIN  — có mấy MAC cùng đáp cho VIP?
#                      >1 MAC = hai máy cùng mang một IP (kịch bản 8).
#
#   [2] ARP CŨ       — MAC mà ROUTER đang ôm cho VIP có khớp với node ĐANG THẬT
#                      SỰ giữ VIP không? Lệch = blackhole Tầng 2 (kịch bản 3),
#                      và đây chính là ca mà mọi dashboard đều báo xanh.
#
# Mã thoát theo chuẩn Nagios/Icinga/Zabbix để cắm thẳng vào hệ giám sát:
#     0 = OK        2 = CRITICAL        3 = UNKNOWN
#
# Ngoài đời chạy nó ở đâu? Trên một máy thứ ba CÙNG SUBNET với VIP (không phải
# trên node HA, không phải trên client remote — cả hai đều không nhìn thấy sự
# thật). Ví dụ: máy giám sát đặt trong VLAN DMZ.
# ==============================================================================
cd "$(dirname "$0")/.."
source scripts/lib.sh

OK=0 ; CRIT=2 ; UNKNOWN=3
ma_thoat=$OK
canh_bao=()

# ------------------------------------------------------------------------------
# [1] Đếm số MAC KHÁC NHAU cùng đáp cho VIP.
#
# arping hỏi ARP broadcast rồi in mỗi câu trả lời một dòng kèm MAC. Mạng khoẻ:
# hỏi 4 lần, đúng 1 MAC đáp. Split-brain: SỐ ĐÁP > SỐ HỎI và có từ 2 MAC.
#
# ⚠️ Phải chạy từ máy CÙNG SUBNET với VIP. Từ subnet khác, gói ARP không bao giờ
#    tới nơi (ARP là Tầng 2, router không chuyển tiếp) -> luôn ra 0 MAC và bạn
#    sẽ tưởng VIP đã chết.
# ------------------------------------------------------------------------------
DAP=$(docker exec $CLIENT_LAN arping -c 4 -I eth0 "$VIP" 2>/dev/null \
      | grep -oiE '\[([0-9a-f]{2}:){5}[0-9a-f]{2}\]' | tr -d '[]' | tr 'A-F' 'a-f' \
      | sort -u)
SO_MAC=$(echo "$DAP" | grep -c . || true)

echo "═══════════════════════════════════════════════════════════════"
echo " KIỂM TRA VIP $VIP"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "[1] SỐ MÁY ĐANG ĐÁP CHO VIP (arping từ máy cùng subnet)"

if [ "$SO_MAC" -eq 0 ]; then
    echo "    ❌ CRITICAL — không máy nào đáp. VIP không tồn tại trên LAN này."
    canh_bao+=("VIP khong ai dap")
    ma_thoat=$CRIT
elif [ "$SO_MAC" -eq 1 ]; then
    echo "    ✅ OK — đúng 1 MAC đáp: $DAP ($(mac_to_node "$DAP"))"
else
    echo "    ❌ CRITICAL — $SO_MAC MAC cùng đáp cho MỘT địa chỉ IP: SPLIT-BRAIN"
    echo "$DAP" | while read -r m; do
        [ -n "$m" ] && echo "         $m  ($(mac_to_node "$m"))"
    done
    canh_bao+=("split-brain: $SO_MAC MAC")
    ma_thoat=$CRIT
fi

# ------------------------------------------------------------------------------
# [2] Bảng ARP của ROUTER có trỏ đúng node đang giữ VIP không?
#
# Đây là cảnh báo QUAN TRỌNG NHẤT của tập, và cũng là cái không hệ giám sát nào
# có sẵn. Ở kịch bản 3, tất cả những thứ dashboard hay theo dõi đều XANH:
# VIP tồn tại, HAProxy sống, backend UP — mà client vẫn chết, chỉ vì một dòng
# trong bảng ARP của router trỏ về máy đã tắt thở.
#
# Ngoài đời lấy MAC của router bằng gì? SNMP (ipNetToMediaPhysAddress),
# hoặc `show ip arp <vip>` qua SSH, hoặc gNMI/NETCONF.
# ------------------------------------------------------------------------------
echo ""
echo "[2] BẢNG ARP CỦA ROUTER CÓ TRỎ ĐÚNG KHÔNG?"

CHU_THAT=$(vip_owner)
MAC_ROUTER=$(router_vip_mac)
THEO_ROUTER=$(mac_to_node "$MAC_ROUTER")

if [ -z "$MAC_ROUTER" ]; then
    echo "    ⚠️  UNKNOWN — router chưa có entry ARP cho VIP (chưa ai gọi qua nó)."
    [ "$ma_thoat" = "$OK" ] && ma_thoat=$UNKNOWN
elif [ "$CHU_THAT" = "(khong ai)" ]; then
    echo "    ❌ CRITICAL — không node nào đang giữ VIP."
    canh_bao+=("khong node nao giu VIP")
    ma_thoat=$CRIT
elif [ "$THEO_ROUTER" = "$CHU_THAT" ]; then
    echo "    ✅ OK — router trỏ $MAC_ROUTER -> $THEO_ROUTER, khớp với thực tế."
else
    echo "    ❌ CRITICAL — LỆCH. Đây là blackhole Tầng 2:"
    echo "         router đang ôm : $MAC_ROUTER -> $THEO_ROUTER"
    echo "         VIP thật nằm ở : $CHU_THAT"
    echo "         Chữa ngay: docker exec lab05-$CHU_THAT arping -U -c 5 -I eth0 $VIP"
    canh_bao+=("ARP router lech: om $THEO_ROUTER nhung VIP o $CHU_THAT")
    ma_thoat=$CRIT
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
case "$ma_thoat" in
    0) echo " KẾT LUẬN: OK — VIP $VIP khoẻ." ;;
    3) echo " KẾT LUẬN: UNKNOWN — chưa đủ dữ liệu để kết luận." ;;
    *) echo " KẾT LUẬN: CRITICAL — ${canh_bao[*]}" ;;
esac
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo " 💡 Cắm vào hệ giám sát:"
echo "      - Chạy trên máy CÙNG SUBNET với VIP, chu kỳ 30-60 giây."
echo "      - Mã thoát 0/2/3 dùng thẳng được cho Nagios, Icinga, Zabbix,"
echo "        hoặc bọc vào textfile collector của Prometheus node_exporter."
echo "      - Cảnh báo [2] là cái đáng tiền nhất: nó bắt được đúng ca mà"
echo "        HAProxy stats, uptime check và ping đều báo XANH."

exit $ma_thoat
