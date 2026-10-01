#!/bin/sh
# ==============================================================================
# MAY DO PHIA CLIENT — chay TRONG container client, de mo suot buoi hoc.
#
#   docker exec -it lab10-client monitor.sh [ten_mien] [nhip_giay]
#
# Moi vong in 5 cot, va 5 cot nay tach duoc toan bo cac ca benh cua tap:
#
#   #CERT  : server GUI RA DAY may cert. 1 = chi co leaf (thieu chuoi).
#            2 = chuan. 3 = co kem ca root (thua, khong sai).
#   NUM    : ma loi cua OpenSSL. 0=ok 10=het han 20=khong tim duoc nguoi ky
#            19=tu ky trong chuoi 21=khong xac minh noi cert dau tien.
#   DEPTH  : ⭐ COT QUAN TRONG NHAT CUA CA TAP. Tang nao trong chuoi bi hong.
#            num=20 DEPTH=0  ->  SERVER gui thieu intermediate.
#            num=20 DEPTH=1  ->  CLIENT thieu root trong trust store.
#            Hai dong nay in ra CHU GIONG HET NHAU. Chi cot nay khac.
#   CURL   : goc nhin cua UNG DUNG.
#
# ⚠️ Moi vong chi mo MOT ket noi TLS. Khi dang co benh, moi ket noi deu phai cho
#    het timeout — goi lap lai se lam mot vong dai hon 10 giay va man hinh dung
#    im dung luc dang quay demo.
# ==============================================================================
TEN=${1:-app.chain.local}
NHIP=${2:-2}
IP=${IP_WEB:-172.28.10.10}
TRUST=/etc/ssl/certs/ca-certificates.crt

# printf %-Ns đếm BYTE khi container chạy locale C -> chữ có dấu làm lệch cột.
# pad: đệm theo số KÝ TỰ (bỏ các byte tiếp nối UTF-8 \200-\277 khi đếm).
pad() {
    n=$(printf %s "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' ')
    printf '%s%*s' "$1" $(( $2 > n ? $2 - n : 0 )) ""
}

echo "$(pad TIME 9) | $(pad "#CERT" 5) | $(pad NUM 4) | $(pad DEPTH 6) | $(pad "THÔNG BÁO" 34) | CURL"
printf -- "------------------------------------------------------------------------------------------------------\n"

while true; do
    TS=$(date -u '+%H:%M:%S')

    # MOT lan bat tay duy nhat: lay ca so cert lan ma verify tu cung ket qua.
    RAW=$(echo | timeout 10 openssl s_client -connect "$IP:443" -servername "$TEN" \
                 -CAfile "$TRUST" -showcerts 2>&1)

    N=$(echo "$RAW" | grep -c '^-----BEGIN CERTIFICATE-----')

    # depth nam o dong TRUOC dong loi — phai doc ca hai cung luc moi ghep dung.
    KQ=$(echo "$RAW" | awk '
        /^depth=/            { d=$0; sub(/^depth=/,"",d); sub(/ .*/,"",d) }
        /^verify error:num=/ && !got {
            n=$0; sub(/^verify error:num=/,"",n); i=index(n,":")
            printf "%s|%s|%s\n", substr(n,1,i-1), d, substr(n,i+1); got=1
        }')
    if [ -z "$KQ" ]; then
        echo "$RAW" | grep -q "Verify return code: 0" && KQ="0|-|ok" || KQ="-|-|không bắt tay được"
    fi
    NUM=$(echo "$KQ" | cut -d'|' -f1)
    DEPTH=$(echo "$KQ" | cut -d'|' -f2)
    MSG=$(echo "$KQ" | cut -d'|' -f3)

    C=$(curl -s -o /dev/null --connect-timeout 3 --max-time 8 \
             -w '%{http_code}' "https://$TEN/" 2>/dev/null)
    RC=$?
    if [ "$RC" = "0" ]; then C="HTTP $C"; else C="exit $RC"; fi

    echo "$(pad "$TS" 9) | $(pad "$N" 5) | $(pad "$NUM" 4) | $(pad "$DEPTH" 6) | $(pad "$MSG" 34) | $C"
    sleep "$NHIP"
done
