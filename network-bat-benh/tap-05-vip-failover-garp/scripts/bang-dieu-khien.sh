#!/usr/bin/env bash
# ==============================================================================
# BẢNG ĐIỀU KHIỂN GỘP — mọi thứ cần theo dõi trong MỘT cửa sổ
#
# Trước đây phải mở 3 terminal: chạy kịch bản / monitor.sh phía client /
# xem-arp-router.sh. Ba cửa sổ cạnh nhau cần hơn 165 cột — chữ nát khi quay
# video, không đọc nổi trên điện thoại.
#
# Script này gộp hai cửa sổ theo dõi thành một bảng rộng đúng 84 cột, còn dư
# chỗ cho terminal chạy lệnh. Tổng cộng chỉ cần 2 pane.
#
#   ./scripts/bang-dieu-khien.sh        # 2 giây một dòng (mặc định)
#   ./scripts/bang-dieu-khien.sh 1      # 1 giây một dòng
#
# ------------------------------------------------------------------------------
# ĐỌC BẢNG NÀY THẾ NÀO
#
#   REMOTE / LAN : hai client gọi VIP. REMOTE ở subnet khác (đi qua router),
#                  LAN ở cùng subnet với VIP. Hai cột này TÁCH NHAU là dấu hiệu
#                  vàng: chỉ một bên chết nghĩa là bảng ARP hai nơi khác nhau.
#
#   ROUTER ÔM    : bảng ARP của router cho VIP — Ổ BỆNH THẬT của tập này.
#
#   VIP THẬT     : node nào đang thực sự mang VIP.
#
#   KẾT LUẬN     : "ARP LỆCH" = router trỏ về một máy KHÁC máy đang giữ VIP.
#                  Đó là blackhole Tầng 2, và là ca mà mọi dashboard báo xanh.
# ==============================================================================
cd "$(dirname "$0")/.."
source scripts/lib.sh

NHIP="${1:-2}"

X_TAT='\033[0m' ; X_XANH='\033[0;32m' ; X_DO='\033[0;31m' ; X_VANG='\033[0;33m'

# MAC của hai node đã được GHIM trong docker-compose.yml nên đọc một lần là đủ.
# Nhờ vậy mỗi nhịp chỉ tốn 4 lệnh docker exec thay vì 8 -> bảng chạy mượt.
A_MAC=$(mac_of $NODE_A) ; B_MAC=$(mac_of $NODE_B)
[ -z "$A_MAC" ] && A_MAC="(node-a chua chay)"
[ -z "$B_MAC" ] && B_MAC="(node-b chua chay)"

ten_theo_mac() {
    case "$1" in
        "")       echo "(chua hoc)" ;;
        "$A_MAC") echo "node-a" ;;
        "$B_MAC") echo "node-b" ;;
        *)        echo "(la)" ;;
    esac
}

# Gọi VIP từ một client, trả về nhãn ngắn gọn.
goi_vip() {
    local OUT RC LB
    OUT=$(docker exec "$1" curl -s -i --connect-timeout 1 --max-time 2 "http://$VIP/" 2>/dev/null)
    RC=$(echo "$OUT" | grep -m1 -oE '^HTTP/[0-9.]+ [0-9]+' | awk '{print $2}')
    LB=$(echo "$OUT" | grep -i '^X-LB-Node:' | tr -d '\r' | awk '{print $2}')
    case "$RC" in
        200) echo "200 ${LB:-?}" ;;
        503) echo "503 NO-BE"    ;;   # CÓ response -> lỗi KHÔNG ở Tầng 2
        "")  echo "BLACKHOLE"    ;;   # không response nào -> frame rơi vào hư vô
        *)   echo "$RC"          ;;
    esac
}

echo "Bảng điều khiển lab 05 — VIP $VIP — nhịp ${NHIP}s — Ctrl-C để thoát"
# ⚠️ Dòng tiêu đề căn lề BẰNG TAY, không dùng printf "%-8s". Lý do: printf đếm
#    BYTE chứ không đếm ô hiển thị, mà mỗi dấu tiếng Việt tốn 2-3 byte -> tiêu
#    đề bị kéo lệch trong khi dòng dữ liệu (thuần ASCII) vẫn thẳng hàng.
printf "GIỜ      REMOTE      LAN        ROUTER(.52) ÔM      VIP THẬT KẾT LUẬN\n"
printf -- "---------------------------------------------------------------------\n"

while true; do
    GIO=$(date +%H:%M:%S)
    R_STAT=$(goi_vip $CLIENT_REMOTE)
    L_STAT=$(goi_vip $CLIENT_LAN)
    R_MAC=$(router_vip_mac)
    CHU=$(vip_owner)
    THEO=$(ten_theo_mac "$R_MAC")

    if [ -z "$R_MAC" ]; then
        KL="router chưa học" ; MAU=$X_VANG
    elif [ "$CHU" = "(khong ai)" ]; then
        KL="KHÔNG AI GIỮ VIP" ; MAU=$X_DO
    elif [ "$THEO" != "$CHU" ]; then
        KL="❌ ARP LỆCH" ; MAU=$X_DO
    elif [ "$R_STAT" = "BLACKHOLE" ] || [ "$L_STAT" = "BLACKHOLE" ]; then
        KL="⚠️  ARP đúng, lỗi chỗ khác" ; MAU=$X_VANG
    elif [ "${R_STAT#503}" != "$R_STAT" ] || [ "${L_STAT#503}" != "$L_STAT" ]; then
        KL="⚠️  503 — mất backend" ; MAU=$X_VANG
    else
        KL="✅ OK" ; MAU=$X_XANH
    fi

    printf "${MAU}%-8s %-11s %-11s %-19s %-8s %s${X_TAT}\n" \
           "$GIO" "$R_STAT" "$L_STAT" "${R_MAC:-(trong)}" "$CHU" "$KL"
    sleep "$NHIP"
done
