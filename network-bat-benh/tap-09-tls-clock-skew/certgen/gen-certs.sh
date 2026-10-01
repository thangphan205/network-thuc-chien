#!/bin/sh
# ==============================================================================
# Sinh toan bo chung chi cho Lab 09.
#
#   gen-certs.sh              -> sinh CA + 5 cert co dinh (chay luc `docker compose up`)
#   gen-certs.sh short [giay] -> sinh RIENG short.crt song <giay> giay ke tu BAY GIO
#                                (MR4 goi lai luc chay, xem mr4-het-han-giua-phien.sh)
#
# NGUYEN TAC THIET KE: khong commit cert vao git.
#   Cert commit san se het han that vao mot ngay nao do -> lab thanh "bom hen
#   gio". Sinh runtime thi:
#     - cert HOP LE luon con han du hoc vien chay lab nam nao,
#     - cert HET HAN co notAfter co dinh trong QUA KHU (01/01/2024) nen no het
#       han VINH VIEN, khong bao gio "song lai".
#
# BAN CO SAU CERT — moi cert hong theo DUNG MOT cach, de tach duoc chu ky:
#
#   server.crt      hop le           CA lab ky, SAN=secure.local, con han
#   expired.crt     HET HAN          notAfter = 01/01/2024 (qua khu co dinh)
#   notyet.crt      CHUA HIEU LUC    notBefore = 01/01/2035 (tuong lai co dinh)
#   wrongname.crt   SAI TEN          CA lab ky, con han, nhung SAN=other.local
#   selfsigned.crt  KHONG AI TIN     tu ky, khong phai CA cua lab
#   short.crt       song <giay> giay sinh theo yeu cau cho MR4
# ==============================================================================
set -eu

OUT=/certs
CN=secure.local
cd "$OUT"

# ------------------------------------------------------------------------------
# Ky mot CSR bang CA cua lab.
#   ky <ten_file> <SAN> <tuy_chon_thoi_han...>
# ------------------------------------------------------------------------------
ky() {
    ten="$1"; san="$2"; shift 2
    openssl req -newkey rsa:2048 -nodes -keyout "$ten.key" -out "$ten.csr" \
        -subj "/CN=$san" 2>/dev/null
    printf 'subjectAltName=DNS:%s\n' "$san" > "$ten.ext"
    openssl x509 -req -in "$ten.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
        -out "$ten.crt" -extfile "$ten.ext" "$@" 2>/dev/null
    rm -f "$ten.csr" "$ten.ext"
}

# ------------------------------------------------------------------------------
# CHE DO `short` — chi sinh lai short.crt, giu nguyen moi cert khac.
#
# Vi sao phai sinh LUC CHAY chu khong sinh san luc `up`?
#   Cert nay chi song vai chuc giay. Neu sinh luc `up` thi den khi hoc vien chay
#   toi MR4 no da het han tu doi nao — va MR4 se khong con chung minh duoc dieu
#   no muon chung minh (phien DANG MO van song sau khi cert het han).
# ------------------------------------------------------------------------------
if [ "${1:-}" = "short" ]; then
    SEC=${2:-90}
    NOW=$(date -u +%s)
    ky short "$CN" \
        -not_before "$(date -u -d "@$NOW"            +%Y%m%d%H%M%SZ)" \
        -not_after  "$(date -u -d "@$((NOW + SEC))"  +%Y%m%d%H%M%SZ)"
    chmod 644 short.crt short.key
    echo "== short.crt sống $SEC giây =="
    openssl x509 -in short.crt -noout -dates
    exit 0
fi

# ------------------------------------------------------------------------------
# 1. Root CA cua lab.
# 825 ngay: gioi han cua CA/Browser Forum cho cert may chu — lay cung con so de
# hoc vien quen mat voi mot thoi han "that".
# ------------------------------------------------------------------------------
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt \
    -subj "/CN=Lab09 Root CA" -days 825 2>/dev/null

# 2. Cert HOP LE — trang thai khoe.
ky server "$CN" -days 825

# ------------------------------------------------------------------------------
# 3. Cert DA HET HAN. notAfter nam trong qua khu CO DINH, khong tinh theo `-days`
#    am. Nho vay no het han giong het nhau tren may cua moi hoc vien.
# ------------------------------------------------------------------------------
ky expired "$CN" -not_before 20230101000000Z -not_after 20240101000000Z

# ------------------------------------------------------------------------------
# 4. Cert CHUA HIEU LUC — notBefore o tuong lai.
#    Ngoai doi gap khi: CA cap nham ngay, hoac may chu build cert bi lech gio
#    ve TUONG LAI. Trieu chung doi xung voi ca het han, va la trieu chung ma
#    client-lech-gio-ve-qua-khu tao ra -> hai nguyen nhan, mot chu ky.
# ------------------------------------------------------------------------------
ky notyet "$CN" -not_before 20350101000000Z -not_after 20360101000000Z

# ------------------------------------------------------------------------------
# 5. Cert SAI TEN MIEN — CA lab ky, con han nguyen ven, chi sai moi SAN.
#    Cai bay quan trong nhat cua tap: `openssl s_client` MAC DINH khong kiem tra
#    ten mien nen no bao "Verify return code: 0 (ok)", trong khi curl va trinh
#    duyet deu tu choi. Xem mr2-sai-ten-mien.sh.
# ------------------------------------------------------------------------------
ky wrongname other.local -days 825

# ------------------------------------------------------------------------------
# 6. Cert TU KY — khong do CA nao cua lab ky.
#    Trinh duyet bao ERR_CERT_AUTHORITY_INVALID chu khong phai ERR_CERT_DATE_*.
#    De day hoc vien doc DUNG ma loi thay vi thay man hinh do la do lech gio.
# ------------------------------------------------------------------------------
openssl req -x509 -newkey rsa:2048 -nodes -keyout selfsigned.key -out selfsigned.crt \
    -subj "/CN=$CN" -days 825 -addext "subjectAltName=DNS:$CN" 2>/dev/null

rm -f ca.srl ./*.csr ./*.ext
# nginx worker (user nginx) can doc duoc key. Trong pham vi lab nen chap nhan;
# tren may that KHONG BAO GIO chmod 644 mot private key.
chmod 644 ./*.crt ./*.key

echo "== Đã sinh xong chứng chỉ của lab 09 =="
for f in server expired notyet wrongname selfsigned; do
    printf '%-11s ' "$f"
    openssl x509 -in "$f.crt" -noout -subject -dates | tr '\n' ' '
    echo ""
done
