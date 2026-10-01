#!/usr/bin/env bash
# ==============================================================================
# MR1 — RESOLVER TU CHOI.  Chu ky: CONNECTION REFUSED.
#
# Tinh huong ngoai doi: may DNS van song, van ping duoc, nhung tien trinh named/
# dnsmasq da chet (het RAM, crash sau khi update, quen enable sau reboot).
#
# Day la ban DNS cua cap tap 01 (DROP -> im lang) vs tap 02 (REJECT -> tra loi
# tu choi ngay). Cung mot muc tieu khong phuc vu duoc, hai chu ky khac han nhau.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR1 — giết tiến trình dnsmasq (container dns VẪN SỐNG)..."
xoa_log_dns
docker exec $DNS dns-stop
echo "   Kiểm chứng máy vẫn sống: $(docker exec $CLIENT ping -c1 -W1 $IP_DNS >/dev/null 2>&1 && echo 'ping tới DNS server: THÔNG' || echo 'ping: KHÔNG THÔNG')"

buoc "CHU KỲ: CONNECTION REFUSED"
in_chu_ky
echo ""
echo "👉 Đọc chu kỳ — so sánh với KB2:"
echo "   • dig mất ~30 ms, KHÔNG phải 2000 ms. Có ai đó trả lời ngay lập tức:"
echo "     kernel của máy DNS gửi về ICMP port unreachable vì cổng 53 đang đóng."
echo "   • curl báo exit 6 'Could not resolve host' — KHÁC KB2 (exit 28)."
echo "   • ping tới DNS server VẪN THÔNG. Máy sống, DỊCH VỤ chết."
echo "     Nếu monitoring của bạn chỉ ping máy DNS thì nó đang báo màu xanh."
echo ""
echo "⚠️  CHÚ Ý 1: MR1 và MR2 cho curl CÙNG MỘT câu 'Could not resolve host' (exit 6)"
echo "    trong khi nguyên nhân khác hẳn nhau. curl KHÔNG đủ để chẩn đoán — phải dig."
echo ""
echo "⚠️  CHÚ Ý 2 (bẫy thực địa): nếu bạn bắn dig LIÊN TỤC nhiều lần trong 1 giây,"
echo "    bạn sẽ thấy 'connection refused' thỉnh thoảng đổi thành 'timed out'."
echo "    Đó KHÔNG phải bệnh đổi — đó là net.ipv4.icmp_ratelimit của Linux, mặc định"
echo "    chỉ cho phát 1 gói ICMP unreachable mỗi giây. Gói thứ 2 trở đi bị kernel nuốt,"
echo "    và 'từ chối' trông giống hệt 'im lặng'."
echo "    -> Khi chẩn đoán, dig THONG THẢ từng lần một. Bắn liên tục là tự làm nhiễu"
echo "       chính bằng chứng của mình."
