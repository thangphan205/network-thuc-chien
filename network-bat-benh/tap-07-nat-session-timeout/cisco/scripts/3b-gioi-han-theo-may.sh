#!/usr/bin/env bash
# ==============================================================================
# KB3 (thuoc) — Gioi han ban dich THEO MAY: may loi tu chiu, nguoi khac khong chet
#
# Dung "max-entries host <ip> <n>". Khong dung "all-host": tren IOL 17.15.1 lenh
# nay hien trong cau hinh nhung khong chan (do duoc bang len 150 khi all-host 20).
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

buoc "KB3 (thuốc) — ip nat translation max-entries host $IP_MAY_LOI $GIOI_HAN_MAY"
r1_cau_hinh "ip nat translation max-entries host $IP_MAY_LOI $GIOI_HAN_MAY"
r1 "show running-config | include ip nat translation" | grep '^ip nat' | sed 's/^/     /' || true

# Ngoai doi: clear * cat luon moi phien dang chay. Uu tien xoa theo may loi.
r1 "clear ip nat translation *" >/dev/null
sleep 1

buoc "KB3 (thuốc) — may-loi lại tạo $SO_FLOW flow"
may_loi_tao_flow
thong_ke | sed 's/^/     /'
echo ""
echo "  Ai đang chiếm bảng:"
ban_dich_theo_may
echo ""
echo "  Kết nối mới của nhan-vien : HTTP $(curl_moi "$NHAN_VIEN")"
echo "  Kết nối mới của may-loi   : HTTP $(curl_moi "$MAY_LOI")"
echo ""
echo "👉 Đọc chữ ký:"
echo "   • Dòng 'host $IP_MAY_LOI' cho used $GIOI_HAN_MAY và missed tăng: máy lỗi bị chặn ở đúng $GIOI_HAN_MAY."
echo "   • nhan-vien trở lại 200: bảng còn chỗ cho người khác."
echo "   • Bản dịch đã tính theo 'host' không cộng vào 'acl LAN', nên giờ đọc dòng 'host'."
echo "   • Đây mới là khoanh vùng. Việc tiếp theo là tìm vì sao máy đó tạo nhiều flow vậy."
