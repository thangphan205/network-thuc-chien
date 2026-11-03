#!/usr/bin/env bash
# ==============================================================================
# KB3 — ⭐ Tran bang NAT: mot may chiem het cho, ca cong ty khong mo duoc ket noi moi
#
# may-loi tao 150 flow UDP, bang chi chua 100. Doc chu ky trong show ip nat
# statistics: used = max allowed, missed tang. Chay 0-setup.sh truoc.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

buoc "KB3 — Trước sự cố: nhan-vien dùng bình thường"
echo "  Kết nối mới của nhan-vien: HTTP $(curl_moi "$NHAN_VIEN")"
thong_ke | sed 's/^/     /'
echo ""
echo "  nhan-vien mở sẵn 1 phiên TCP (GET #1 ngay, GET #2 sau 25 giây)..."
mo_phien_cu

buoc "KB3 — may-loi tạo $SO_FLOW flow UDP, mỗi flow một source port"
may_loi_tao_flow
thong_ke | sed 's/^/     /'
echo ""
echo "  Ai đang chiếm bảng (show ip nat translations):"
ban_dich_theo_may

buoc "KB3 — Triệu chứng phía nhan-vien"
echo "  Kết nối MỚI : HTTP $(curl_moi "$NHAN_VIEN")   (000 = không mở được)"
echo "  Ping        : nhận $(ping_nhan_vien)/2 gói"
echo "  Phiên CŨ    : $(doc_phien_cu)/2 phản hồi 200   (GET #2 gửi lúc bảng đang đầy)"
echo ""
thong_ke | sed 's/^/     /'
echo ""
echo "👉 Đọc chữ ký:"
echo "   • 'acl LAN: used' bằng 'max allowed' → bảng đã đầy."
echo "   • 'missed' tăng sau mỗi lần thử → bản dịch mới đang bị từ chối."
echo "   • Phiên cũ sống, phiên mới chết, ping cũng chết vì ICMP cũng cần bản dịch."
echo "   • Router không ghi syslog %NAT nào: không đọc thống kê thì không biết."
echo "   • Đối lập với KB2 (NAT timeout): ở đó phiên CŨ chết, phiên MỚI vẫn chạy."
echo ""
echo "👉 Chữa: ./scripts/3b-gioi-han-theo-may.sh"
