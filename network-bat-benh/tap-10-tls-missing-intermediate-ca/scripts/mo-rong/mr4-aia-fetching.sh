#!/usr/bin/env bash
# ==============================================================================
# MR4 — AIA FETCHING: vi sao MAY TINH VAO DUOC ma DIEN THOAI thi khong.
#
# Day la loi giai cho canh mo dau cua tap.
#
# Server gui thieu intermediate — y het KB2. Nhung lan nay leaf mang them mot
# dong extension:
#       Authority Information Access:
#           CA Issuers - URI:http://aia.lab.local/intermediateCA.der
#
# Dong do la mot tam giay ghi "cert cua nguoi ky toi tai o day". Trinh duyet doc
# no, TU TAI cert trung gian ve, tu va lai chuoi bi thieu, roi hien o khoa xanh
# nhu chua co chuyen gi. Curl / Python requests / Java / phan lon mobile SDK
# KHONG lam buoc do — chung coi viec gui du chuoi la trach nhiem cua server.
#
# ⚠️ VI SAO DAY LA CA BENH NGUY HIEM NHAT TRONG TAP:
#    No khong hong tren may cua nguoi di deploy. Ky su test bang Chrome, thay
#    khoa xanh, dong may ve. Loi chi no o phia nguoi dung cuoi va o cac dich vu
#    backend goi API — tuc la o dung nhung cho khong ai nhin thay log.
#    Va no khong bao gio tu khoi: server van dang gui thieu, moi ngay, cho moi
#    ket noi. Chi la mot so client tu vet duoc thoi.
#
#    Ngay ca trinh duyet cung khong dam bao: Firefox tren mot so nen tang KHONG
#    fetch AIA. Neu may chu AIA cham hoac chet thi trang tai lau ro ret roi moi
#    hien khoa xanh — mot kieu "web luc nhanh luc cham" rat kho lan ra nguyen nhan.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR4 — server chi gui LEAF, nhung leaf co mang URL AIA..."
cai_root
dat_chuoi aia

buoc "CHU KY: THIEU CHUOI — NHUNG CO TAM GIAY CHI DUONG"
in_chu_ky

buoc "DIEN LAI CAC BUOC MA TRINH DUYET LAM TU DONG"
RAW=$(_bat_tay)
URL=$(aia_url "$RAW")
echo "  [1] Doc URL AIA nam trong cert cua server:"
echo "        $URL"
echo ""
echo "  [2] Tai cert trung gian ve tu URL do (dang DER, theo RFC 5280):"
_trong_client "curl -s -o /tmp/int.der -w '        HTTP %{http_code}, %{size_download} bytes\n' '$URL'"
_trong_client "openssl x509 -inform DER -in /tmp/int.der -noout -subject -issuer" | sed 's/^/        /'
echo ""
echo "  [3] Verify lai chuoi — mot lan KHONG co, mot lan CO cert vua tai ve."
# Lay dung cai leaf ma server gui ra day, roi thu verify hai kieu tren cung no.
_trong_client "openssl x509 -inform DER -in /tmp/int.der -out /tmp/int.pem"
_trong_client "echo | openssl s_client -connect $IP_WEB:443 -servername $TEN 2>/dev/null | sed -n '/BEGIN CERT/,/END CERT/p' > /tmp/leaf.pem"
echo "        Truoc — chi voi nhung gi server gui (dung y curl):"
_trong_client "openssl verify -CAfile $TRUST /tmp/leaf.pem 2>&1 | sed 's/^/          /'"
echo "        Sau  — them cert tai tu AIA (dung y trinh duyet):"
_trong_client "openssl verify -CAfile $TRUST -untrusted /tmp/int.pem /tmp/leaf.pem 2>&1 | sed 's/^/          /'"
echo ""
echo "  [4] Va day la ung dung that: va cert AIA vao bundle roi goi lai."
_trong_client "cat $TRUST /tmp/int.pem > /tmp/bundle.pem"
_trong_client "curl -s -o /dev/null -w '        curl --cacert bundle-co-AIA  ->  HTTP %{http_code}\n' --cacert /tmp/bundle.pem https://$TEN/ 2>&1 || true"
echo ""
echo "👉 Doc chu ky:"
echo "   • Chuoi tren day van chi 1 cert — server VAN dang gui thieu, y het KB2."
echo "   • Khac KB2 o dung mot dong: cert co AIA. Dong do khong sua duoc loi,"
echo "     no chi cho MOT SO client cach tu vet lay."
echo "   • curl van chet. Trinh duyet thi vao duoc. Cung mot server."
echo "   • Chua: van la tro sang fullchain. AIA KHONG phai cach chua — no la"
echo "     thu che mat trieu chung o dung cho ban hay nhin nhat."
echo ""
echo "   🧠 Cau hoi tu kiem tra khi ai do bao 'may em vao binh thuong':"
echo "        'Anh test bang trinh duyet hay bang curl?'"
echo "      Hai cong cu do KHONG kiem tra cung mot thu."
