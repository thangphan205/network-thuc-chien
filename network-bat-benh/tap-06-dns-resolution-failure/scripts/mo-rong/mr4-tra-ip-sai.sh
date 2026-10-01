#!/usr/bin/env bash
# ==============================================================================
# MR4 — DNS TRA LOI THANH CONG NHUNG TRA SAI DIA CHI.  ⭐ Ca dat gia nhat.
#
# Tinh huong ngoai doi: doi server, ban ghi A cu chua duoc cap nhat (hoac cap
# nhat roi nhung ai do rollback). `dig` xanh muot, `ping` thong, khong mot dong
# loi nao ve DNS. Va ban di soi firewall ca buoi chieu.
#
# Hai nua cua ca benh, hai trieu chung khac han:
#   A. Dia chi cu con MAY SONG   -> HTTP 200. Loi im lang nhat trong nghe.
#   B. Dia chi cu khong con may  -> curl treo roi exit 28 (connect timeout).
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR4-A — sửa bản ghi A: $TEN -> $IP_WEB_CU (server CŨ, vẫn đang bật)..."
xoa_log_dns
doi_ban_ghi "$TEN" "$IP_WEB_CU"
sleep 1

buoc "CHU KỲ 6-A: NOERROR + HTTP 200 + NỘI DUNG SAI"
in_chu_ky
echo ""
echo "👉 Đọc chu kỳ — đây là lý do ca này khó lần:"
echo "   • dig status = NOERROR, Query time ~0 ms. DNS 'khỏe' theo mọi thước đo."
echo "   • curl trả về http_code=200. Giám sát uptime của bạn đang báo MÀU XANH."
echo "   • Chỉ có dòng 'trang nhận được' tố giác: bạn đang ở SERVER CŨ."
echo "   • So sánh IP theo dig ($IP_WEB_CU) với IP ĐÚNG của dịch vụ ($IP_WEB) là"
echo "     bước chẩn đoán duy nhất có giá trị. Không lệnh mạng nào báo bạn điều đó —"
echo "     bạn phải BIẾT địa chỉ đúng là bao nhiêu."

echo ""
echo "🚨 MR4-B — sửa bản ghi A: $TEN -> $IP_MA (địa chỉ không còn máy nào)..."
xoa_log_dns
doi_ban_ghi "$TEN" "$IP_MA"
sleep 1

buoc "CHU KỲ 6-B: NOERROR + CURL TREO RỒI TIMEOUT"
in_chu_ky
echo ""
echo "👉 Doc chu ky:"
echo "   • dig VẪN xanh: NOERROR, trả về $IP_MA trong ~0 ms. Khâu phân giải HOÀN HẢO."
echo "   • curl exit 28 nhưng lần này là CONNECT timeout, không phải resolve timeout."
echo "     Phân biệt bằng curl -v: nó in 'Trying $IP_MA:80...' rồi mới treo."
echo "     Nếu là KB2, curl chưa bao giờ in được dòng 'Trying' nào."
echo ""
echo "🔑 Bài học chung của MR4: 'dig chạy tốt' KHÔNG đồng nghĩa 'DNS đúng'."
echo "   Câu hỏi phải hỏi là: dig trả về ĐÚNG IP không?"
