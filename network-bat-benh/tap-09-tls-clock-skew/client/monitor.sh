#!/bin/sh
# ==============================================================================
# MAY DO PHIA CLIENT — chay TRONG container client, de mo suot buoi hoc.
#
#   docker exec -it lab09-client monitor.sh [ten_mien] [nhip_giay]
#
# Moi vong in 5 cot, va 5 cot nay tach duoc toan bo cac ca benh cua tap:
#
#   GIO CLIENT : dong ho ma tien trinh dang dung. Cot goc — moi ket luan ve
#                "cert het han" deu la ket luan TUONG DOI so voi cot nay.
#   HAN CERT   : notBefore -> notAfter DOC TU DAY, khong doc tu file tren dia.
#                Doc tu day moi biet server DANG serve cai gi (co the khac voi
#                cai ban nghi no serve).
#   VERIFY     : ma tra ve cua OpenSSL. 0=ok 9=chua hieu luc 10=het han
#                18/19/20=khong tin duoc CA.
#   CURL       : goc nhin cua UNG DUNG. Khac VERIFY o cho no CO kiem tra ten mien.
#                VERIFY=0 ma CURL=60 => loi ten mien, khong phai loi thoi han.
#
# ⚠️ Moi vong chi mo MOT ket noi TLS. Khi dang co benh, moi ket noi deu phai cho
#    het timeout — goi lap lai se lam mot vong dai hon 10 giay va man hinh dung
#    im dung luc dang quay demo.
# ==============================================================================
TEN=${1:-secure.local}
NHIP=${2:-2}
IP=${IP_WEB:-172.28.9.10}
CA=/etc/ssl/lab/ca.crt

# printf %-Ns đếm BYTE khi container chạy locale C -> chữ có dấu làm lệch cột.
# pad: đệm theo số KÝ TỰ (bỏ các byte tiếp nối UTF-8 \200-\277 khi đếm).
pad() {
    n=$(printf %s "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' ')
    printf '%s%*s' "$1" $(( $2 > n ? $2 - n : 0 )) ""
}

echo "$(pad TIME 9) | $(pad "GIỜ CLIENT" 19) | $(pad "HẠN CERT (từ dây)" 23) | $(pad VERIFY 26) | CURL"
printf -- "---------------------------------------------------------------------------------------------------------\n"

while true; do
    TS=$(date '+%H:%M:%S')
    GIO=$(date '+%Y-%m-%d %H:%M:%S')

    # MOT lan bat tay duy nhat: lay ca ma verify lan chinh cert tu cung ket qua.
    RAW=$(echo | timeout 8 openssl s_client -connect "$IP:443" -servername "$TEN" \
                 -CAfile "$CA" 2>&1)

    V=$(echo "$RAW" | sed -n 's/.*Verify return code: //p' | head -1)
    [ -z "$V" ] && V="(không bắt tay được)"

    # openssl in ngay dang "Sep  4 09:20:22 2026 GMT". busybox date KHONG parse
    # duoc dinh dang do (no im lang tra ve chuoi goc), nen tu cat bang awk:
    #   $1=thang $2=ngay $3=gio $4=nam  ->  "4/Sep/2026"
    # Gon lai cho vua cot, va van doc duoc bang mat.
    D=$(echo "$RAW" | sed -n '/BEGIN CERT/,/END CERT/p' \
        | openssl x509 -noout -dates 2>/dev/null \
        | sed -n 's/^not\(Before\|After\)=//p' \
        | awk '{printf "%s/%s/%s\n", $2, $1, $4}' \
        | paste -sd'>' - 2>/dev/null)
    [ -z "$D" ] && D="(không lấy được)"

    C=$(curl -s -o /dev/null --connect-timeout 3 --max-time 8 \
             -w '%{http_code}' "https://$TEN/" 2>/dev/null)
    RC=$?
    if [ "$RC" = "0" ]; then C="HTTP $C"; else C="exit $RC"; fi

    echo "$(pad "$TS" 9) | $(pad "$GIO" 19) | $(pad "$D" 23) | $(pad "$V" 26) | $C"
    sleep "$NHIP"
done
