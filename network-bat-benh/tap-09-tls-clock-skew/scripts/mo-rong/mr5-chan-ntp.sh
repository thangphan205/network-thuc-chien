#!/usr/bin/env bash
# ==============================================================================
# MR5 — NGUYEN NHAN GOC CUA KB3: UDP 123 BI CHAN, DONG HO TROI TU DO.
#
# KB3 cho thay TRIEU CHUNG cua lech gio. MR5 cho thay NGUON GOC cua no.
#
# Tinh huong ngoai doi (day la ly do so 1 khien dong ho server troi):
#   - Firewall/security group chi mo TCP, quen mo UDP 123 chieu ra.
#   - Mang cach ly hoan toan, khong co NTP server noi bo nao.
#   - Cloud image tro vao pool.ntp.org nhung VPC khong co duong ra Internet.
#   - chronyd/systemd-timesyncd bi tat trong lan "toi uu dich vu" nao do.
#
# Dong ho tinh the (RTC) troi khoang 1-2 giay/ngay khi khong duoc keo lai. Nghe
# khong dang ke — nhung sau vai thang la vai phut, va sau mot lan het pin CMOS
# la vai NAM. Do la luc cert bat dau "het han" mot cach kho hieu.
#
# ⚠️ Kich ban nay KHONG doi dong ho. No chi chan duong hoi gio, roi cho thay
#    hau qua: may mat kha nang BIET minh dang sai. Container dung chung dong ho
#    kernel voi may that nen khong bao gio duoc phep dat lai gio. Muon THAY hau
#    qua cua viec troi gio thi chay KB3 (faketime).
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR5 — chặn UDP 123 đi ra từ client (mô phỏng firewall quên mở NTP)..."
dat_cert good
GIO_GIA=""

buoc "TRƯỚC KHI CHẶN — client hỏi được nguồn giờ thật"
mo_lai_ntp
echo "  chronyd -Q 'server $IP_NTP iburst'"
hoi_gio_ntp | sed 's/^/    /'
echo ""
echo "  ✅ Hỏi được => máy TỰ BIẾT được nó đang sai bao nhiêu, và tự kéo lại được."

echo ""
echo "🚨 Đặt luật chặn..."
docker exec $CLIENT iptables -A OUTPUT -p udp --dport 123 -j DROP
docker exec $CLIENT iptables -S OUTPUT 2>/dev/null | sed 's/^/    /' || true

buoc "SAU KHI CHẶN — client hỏi giờ"
echo "  chronyd -Q 'server $IP_NTP iburst'   (chờ tới 8 giây...)"
hoi_gio_ntp | sed 's/^/    /'
echo ""
echo "  ❌ Không hỏi được nguồn nào. Từ giờ máy CHỈ CÒN đồng hồ tinh thể của nó."

buoc "TRẠNG THÁI TLS NGAY LÚC NÀY"
in_chu_ky
echo ""
echo "👉 Đọc chữ ký:"
echo "   • TLS vẫn 200 OK. Chặn NTP KHÔNG làm hỏng TLS ngay lập tức — đây chính"
echo "     là chỗ nguy hiểm: sự cố được GIEO hôm nay, nó nổ ra sau vài tháng."
echo "   • Chặn NTP là một sự cố IM LẶNG. Không alert nào kêu, không log nào đỏ."
echo "     Nó chỉ lộ diện khi đồng hồ đã trôi đủ xa để đẩy cert ra ngoài hạn."
echo ""
echo "   🔎 Kiểm tra trên máy thật:"
echo "     timedatectl                      # 'System clock synchronized: yes/no'"
echo "     chronyc tracking                 # 'Leap status: Normal' + độ lệch"
echo "     chronyc sources -v               # có nguồn nào đang được chọn không"
echo "     ss -unp | grep :123              # có tiến trình nào đang nói NTP không"
echo "     ntpdate -q pool.ntp.org          # hỏi thử một phát"
echo ""
echo "   🧯 Chữa:"
echo "     - Mở UDP 123 CHIỀU RA trên firewall/security group (rất hay bị quên)."
echo "     - Bật lại chronyd/systemd-timesyncd, đặt nó khởi động cùng hệ thống."
echo "     - Mạng cách ly: dùng NTP server nội bộ, trỏ toàn bộ máy vào đó."
echo "     - Thay pin CMOS nếu máy nhảy về mốc rất xa sau mỗi lần tắt nguồn."
echo ""
echo "   Reset (gỡ luật chặn): ./scripts/0-setup.sh"
