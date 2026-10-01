#!/usr/bin/env bash
# ==============================================================================
# KB2 — SERVER SERVE CERT DA HET HAN.  Chu ky: verify 10, LECH GIO ~0.
#
# Tinh huong ngoai doi: cert Let's Encrypt het han vi cron gia han that bai am
# tham 2 thang truoc, hoac cert mua 1 nam khong ai dat lich nhac.
#
# Day la ca benh ma AI CUNG doan dau tien khi thay man hinh do. No that su pho
# bien — nhung no chi la MOT trong hai nguyen nhan sinh ra ma verify 10.
# KB3 sinh ra DUNG ma do voi mot cert con han nguyen ven. Thu tach hai ca benh
# nay chi co mot: DO LECH GIO.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB2 — cho nginx serve expired.crt (notAfter = 01/01/2024)..."
dat_cert expired
GIO_GIA=""

buoc "CHỮ KÝ: CERT HẾT HẠN THẬT (thủ phạm ở SERVER)"
in_chu_ky
echo ""
echo "👉 Đọc chữ ký:"
echo "   • TCP 443 vẫn MỞ, bắt tay TLS vẫn chạy tới bước Certificate. Tầng 3/4"
echo "     hoàn toàn khỏe — đừng đi soi firewall, đừng đi soi route."
echo "   • verify 10 + LỆCH GIỜ ~0  ->  hai đồng hồ khớp nhau, nên notAfter là"
echo "     SỰ THẬT. Cert hết hạn thật. Thủ phạm ở phía server."
echo "   • Chữa: thay cert mới. KHÔNG phải đồng bộ NTP."
echo ""
echo "   ⚠️ So sánh với KB3 (./scripts/3-client-lech-gio.sh): KB3 cho ra ĐÚNG mã"
echo "      verify 10 này, nhưng cert lúc đó còn hạn thêm hơn 2 năm nữa."
echo "      Nếu bạn chỉ nhìn mã lỗi mà không nhìn đồng hồ, bạn sẽ đi thay một cái"
echo "      cert hoàn toàn không có vấn đề gì."
