#!/usr/bin/env bash
# ==============================================================================
# SMOKE TEST KB3 — dung lai lab, chay ca benh + thuoc, khang dinh tung chu ky.
# Hanh vi bo dem NAT doi theo ban IOS: doi image thi chay file nay truoc khi quay.
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

HONG=0
PASS=0

kiem() {   # kiem <ten> <thuc_te> <mong_doi>
    if [ "$2" = "$3" ]; then
        printf "   ✅ %s%*s %s\n" "$1" $((40 - ${#1})) "" "$2"
        PASS=$((PASS + 1))
    else
        printf "   ❌ %s%*s %s   (mong đợi: %s)\n" "$1" $((40 - ${#1})) "" "$2" "$3"
        HONG=$((HONG + 1))
    fi
}

echo "=============================================="
echo "🧪 TEST TẬP 07 — KB3: tràn bảng NAT trên Cisco"
echo "=============================================="

./scripts/0-setup.sh >/dev/null || exit 1

echo ""
echo "Trước sự cố:"
kiem "nhan-vien kết nối mới" "$(curl_moi "$NHAN_VIEN")" "200"
read -r DUNG THIEU <<< "$(doc_gioi_han 'acl LAN')"
kiem "acl LAN missed" "${THIEU:-rỗng}" "0"

mo_phien_cu
may_loi_tao_flow

echo ""
echo "KB3 — ⭐ bảng đầy:"
read -r DUNG THIEU <<< "$(doc_gioi_han 'acl LAN')"
kiem "acl LAN used" "${DUNG:-rỗng}" "$GIOI_HAN_BANG"
[ "${THIEU:-0}" -gt 0 ] && TANG=có || TANG=không
kiem "acl LAN missed > 0" "$TANG" "có"
kiem "nhan-vien kết nối mới" "$(curl_moi "$NHAN_VIEN")" "000"
kiem "nhan-vien ping nhận" "$(ping_nhan_vien)" "0"
kiem "nhan-vien phiên cũ" "$(doc_phien_cu)" "2"
kiem "dòng syslog %NAT" "$(r1 'show logging' | grep -c '%NAT' || true)" "0"

echo ""
echo "KB3 — thuốc: giới hạn theo máy:"
r1_cau_hinh "ip nat translation max-entries host $IP_MAY_LOI $GIOI_HAN_MAY"
r1 "clear ip nat translation *" >/dev/null
sleep 1
may_loi_tao_flow
read -r DUNG THIEU <<< "$(doc_gioi_han "host $IP_MAY_LOI")"
kiem "host may-loi used" "${DUNG:-rỗng}" "$GIOI_HAN_MAY"
[ "${THIEU:-0}" -gt 0 ] && TANG=có || TANG=không
kiem "host may-loi missed > 0" "$TANG" "có"
kiem "nhan-vien kết nối mới" "$(curl_moi "$NHAN_VIEN")" "200"
kiem "may-loi kết nối mới" "$(curl_moi "$MAY_LOI")" "000"

echo ""
echo "=============================================="
if [ "$HONG" -eq 0 ]; then
    echo "✅ TẤT CẢ $PASS PHÉP THỬ ĐỀU ĐÚNG."
    exit 0
else
    echo "❌ $HONG PHÉP THỬ SAI (và $PASS đúng)."
    echo "   Bảng vân tay trong README đang không khớp với lab — sửa trước khi quay."
    exit 1
fi
