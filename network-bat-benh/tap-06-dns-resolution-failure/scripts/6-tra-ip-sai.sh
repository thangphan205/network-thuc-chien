#!/usr/bin/env bash
# ==============================================================================
# KB6 — DNS TRA LOI THANH CONG NHUNG TRA SAI DIA CHI.  ⭐ Ca dat gia nhat.
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
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB6-A — sua ban ghi A: $TEN -> $IP_WEB_CU (server CU, van dang bat)..."
xoa_log_dns
doi_ban_ghi "$TEN" "$IP_WEB_CU"
sleep 1

buoc "CHU KY 6-A: NOERROR + HTTP 200 + NOI DUNG SAI"
in_chu_ky
echo ""
echo "👉 Doc chu ky — day la ly do ca nay kho lan:"
echo "   • dig status = NOERROR, Query time ~0 ms. DNS 'khoe' theo moi thuoc do."
echo "   • curl tra ve http_code=200. Giam sat uptime cua ban dang bao MAU XANH."
echo "   • Chi co dong 'trang nhan duoc' to giac: ban dang o SERVER CU."
echo "   • So sanh IP theo dig ($IP_WEB_CU) voi IP DUNG cua dich vu ($IP_WEB) la"
echo "     buoc chan doan duy nhat co gia tri. Khong lenh mang nao bao ban dieu do —"
echo "     ban phai BIET dia chi dung la bao nhieu."

echo ""
echo "🚨 KB6-B — sua ban ghi A: $TEN -> $IP_MA (dia chi khong con may nao)..."
xoa_log_dns
doi_ban_ghi "$TEN" "$IP_MA"
sleep 1

buoc "CHU KY 6-B: NOERROR + CURL TREO ROI TIMEOUT"
in_chu_ky
echo ""
echo "👉 Doc chu ky:"
echo "   • dig VAN xanh: NOERROR, tra ve $IP_MA trong ~0 ms. Khau phan giai HOAN HAO."
echo "   • curl exit 28 nhung lan nay la CONNECT timeout, khong phai resolve timeout."
echo "     Phan biet bang curl -v: no in 'Trying $IP_MA:80...' roi moi treo."
echo "     Neu la KB2, curl chua bao gio in duoc dong 'Trying' nao."
echo ""
echo "🔑 Bai hoc chung cua KB6: 'dig chay tot' KHONG dong nghia 'DNS dung'."
echo "   Cau hoi phai hoi la: dig tra ve DUNG IP khong?"
