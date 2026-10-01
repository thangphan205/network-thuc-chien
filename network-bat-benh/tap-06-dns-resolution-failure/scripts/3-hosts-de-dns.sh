#!/usr/bin/env bash
# ==============================================================================
# KB3 — /etc/hosts DE LEN DNS.  Chu ky: dig DUNG nhung ung dung di SAI.
#
# Tinh huong ngoai doi: ai do them mot dong vao /etc/hosts hoi debug thang truoc
# roi quen xoa. Hoac cong cu trien khai ghi vao do. DNS server hoan toan vo can.
#
# Co che: ung dung KHONG hoi DNS truc tiep. No goi getaddrinfo(), va ham nay di
# theo thu tu trong /etc/nsswitch.conf — mac dinh la `hosts: files dns`, tuc la
# /etc/hosts TRUOC, DNS SAU. Con `dig` thi hoi THANG nameserver, KHONG BAO GIO
# doc /etc/hosts. Do la ly do hai cong cu noi hai chuyen khac nhau.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB3 — thêm một dòng để quên trong /etc/hosts của client..."
xoa_log_dns
them_hosts "$IP_WEB_CU"
echo "   /etc/hosts hiện có:"
docker exec $CLIENT grep lab.local /etc/hosts | sed 's/^/     /'

buoc "CHU KỲ: dig ĐÚNG, ỨNG DỤNG SAI"
in_chu_ky
echo ""
echo "  --- Thứ tự tra cứu tên của hệ thống (/etc/nsswitch.conf) ---"
docker exec $CLIENT grep '^hosts:' /etc/nsswitch.conf | sed 's/^/  /'

echo ""
echo "👉 Đọc chu kỳ:"
echo "   • IP theo dig     = $IP_WEB  (dig hỏi thẳng server — server trả ĐÚNG)"
echo "   • IP theo NSS/app = $IP_WEB_CU  (ứng dụng đọc /etc/hosts TRƯỚC)"
echo "   • Hai dòng này LỆCH NHAU. Đó là toàn bộ chẩn đoán của KB3."
echo "   • curl 200 nhưng vào SERVER CŨ — giống hệt MR4-A về triệu chứng bên ngoài,"
echo "     nhưng khác hẳn ở chỗ: MR4 sửa trên DNS SERVER, KB3 sửa trên MÁY CLIENT."
echo ""
echo "🔑 Bài học: nếu bạn chỉ dùng dig để kiểm tra, bạn sẽ kết luận 'DNS ổn' và"
echo "   đóng ticket. Lệnh đúng để kiểm tra là getent hosts <tên> — nó đi đúng"
echo "   con đường mà ứng dụng đi."
echo ""
echo "   Sắp xếp 3 câu hỏi theo thứ tự:"
echo "     1. getent hosts $TEN   -> ứng dụng THẬT SỰ dùng IP nào?"
echo "     2. dig $TEN            -> DNS server nói gì?"
echo "     3. Lệch nhau?          -> thủ phạm nằm TRÊN MÁY CLIENT (hosts/nscd),"
echo "                               không phải trên DNS server."
