#!/usr/bin/env bash
# ==============================================================================
# MR2 — NXDOMAIN.  Chu ky: server TRA LOI, va cau tra loi la "ten do khong ton tai".
#
# Tinh huong ngoai doi: go sai ten mien, quen tao ban ghi A cho dich vu moi, hoac
# ai do xoa nham mot dong trong zone.
#
# Diem quan trong: day KHONG phai su co mang. Moi thu o L2/L3/L4 deu hoan hao.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

TEN_SAI=wed.lab.local     # go nham 'web' thanh 'wed'
echo "🚨 MR2 — hỏi một tên KHÔNG có trong zone: $TEN_SAI"
xoa_log_dns

buoc "CHU KỲ: NXDOMAIN"
in_chu_ky "$TEN_SAI"
echo ""
echo "  --- Góc nhìn phía DNS server ---"
log_dns 4 | sed 's/^/  /'
echo ""
echo "👉 Đọc chu kỳ:"
echo "   • dig status = NXDOMAIN và mất ~1 ms. NHANH = server SỐNG, ĐÃ trả lời."
echo "     Đối lập hoàn toàn với KB2 (2000 ms, không ai trả lời)."
echo "   • query tới server > 0, log server ghi rõ 'is NXDOMAIN'."
echo "     Bạn có bằng chứng hai chiều: client hỏi, server đáp."
echo "   • curl báo exit 6 — GIỐNG HỆT MR1, nhưng dig nói hai chuyện khác hẳn."
echo ""
echo "ℹ️  Ghi chú kỹ thuật: dnsmasq trả NXDOMAIN với AUTHORITY: 0 (không kèm SOA),"
echo "    đúng như một resolver đệm/chuyển tiếp. Một máy chủ CÓ THẨM QUYỀN thật"
echo "    (BIND, PowerDNS) sẽ kèm thêm bản ghi SOA trong phần AUTHORITY."
echo ""
echo "👉 Chẩn đoán: ./scripts/test.sh $TEN_SAI"
echo "   (PHẢI truyền tên — test.sh mặc định hỏi $TEN, tên đó vẫn khỏe)"
