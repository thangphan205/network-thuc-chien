#!/usr/bin/env bash
# ==============================================================================
# Hang so & ham dung chung cho cac script cua tap 9
#
#   172.28.9.0/24 — mot LAN phang, khong router. Moi thu o L2/L3/L4 deu dung
#   tuyet doi. Ca benh nam o TANG 5/6: khau XAC THUC CHUNG CHI trong bat tay TLS.
#
# TU TUONG CUA CA TAP:
#   "Chung chi het han" KHONG phai mot su that tuyet doi. No la mot PHEP SO SANH
#   giua hai thu:  [notBefore, notAfter] cua cert   vs   DONG HO CUA BEN KIEM TRA.
#   Sai ve nao trong hai ve cung cho ra DUNG MOT thong bao loi. Vi vay cau hoi
#   dau tien khi debug cert khong bao gio la "cert het han chua?" ma la:
#   "dong ho hai dau dang tra ve gi?"
# ==============================================================================
WEB=lab09-web-server
CLIENT=lab09-client
NTP=lab09-ntp

IP_WEB=172.28.9.10
IP_CLIENT=172.28.9.20
IP_NTP=172.28.9.30

TEN=secure.local           # ten mien chinh, khop SAN cua server.crt
TEN_SAI=other.local        # ten khop SAN cua wrongname.crt — dung cho MR2
PORT_HOST=8443             # cong publish ra may that (443 trong lab-net)

CA=/etc/ssl/lab/ca.crt     # duong dan CA BEN TRONG container client
CA_HOST=nginx/ssl/ca.crt   # duong dan CA tren may that
NGINX_CONF=nginx/nginx.conf

# GIO_GIA: dong ho gia ap len tien trinh curl/openssl trong client.
#   Rong  = dung dong ho that cua container (= dong ho may hoc vien).
#   Co gia tri (vd '2035-01-01 00:00:00') = gia lap client bi lech gio.
# Cac kich ban dat bien nay TRUOC khi goi in_chu_ky.
GIO_GIA=""

# ==============================================================================
# PHAN 1 — DIEU KHIEN LAB
# ==============================================================================

# ------------------------------------------------------------------------------
# Doi cert ma nginx dang serve.   dat_cert good | expired | notyet | ...
#
# Vi sao `restart` chu khong `nginx -s reload`?
#   nginx.conf duoc bind-mount tu may that. Tren Docker Desktop (macOS/Windows)
#   lop chia se file co the tra ve NOI DUNG CU cho tien trinh dang chay, nen
#   reload doi khi nap lai dung cai cu — loi chi xuat hien tren may cua mot vai
#   hoc vien va cuc ky kho lan. restart tao tien trinh moi, doc lai tu dau.
# ------------------------------------------------------------------------------
dat_cert() {
    cp "nginx/conf/$1.conf" "$NGINX_CONF"
    docker compose restart web-server >/dev/null 2>&1
    cho_web_san_sang
    dam_bao_ca
}

# ------------------------------------------------------------------------------
# Cai CA cua lab vao TRUST STORE cua client (idempotent — lan sau la no-op).
#
# Vi sao khong dinh --cacert vao moi lenh curl?
#   Vi ngoai doi khong ai lam the. Ngoai doi CA nam trong trust store cua may, va
#   lenh la `curl https://host/` tran. Neu lab bat hoc vien go --cacert thi:
#     - hoc vien mang thoi quen sai ra moi truong that,
#     - va MR3 (cert tu ky) se that bai vi "quen tham so", che mat ly do THAT la
#       "khong ai tin nguoi ky cert nay".
#
# CA duoc sinh luc chay nen khong the nhet san vao image — phai cai o day.
# ------------------------------------------------------------------------------
dam_bao_ca() {
    docker exec $CLIENT sh -c \
        "cmp -s /etc/ssl/lab/ca.crt /usr/local/share/ca-certificates/lab09-ca.crt 2>/dev/null || { cp /etc/ssl/lab/ca.crt /usr/local/share/ca-certificates/lab09-ca.crt && update-ca-certificates; }" \
        >/dev/null 2>&1 || true
    return 0
}

# nginx can vai tram ms de mo lai cong 443. Khong cho thi lenh test ngay sau do
# se bao "Connection refused" va hoc vien tuong day la trieu chung cua ca benh.
cho_web_san_sang() {
    local i
    for i in $(seq 1 30); do
        if docker exec $CLIENT sh -c "nc -z $IP_WEB 443" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.3
    done
    return 0
}

# Cert ma nginx DANG duoc cau hinh de serve (doc tu file cau hinh).
cert_dang_dat() {
    sed -n 's#.*ssl_certificate  *\(.*\)/\([a-z]*\)\.crt;#\2#p' "$NGINX_CONF" 2>/dev/null | head -1
    return 0
}

# Go moi luat chan UDP 123 do MR5 dat ra. Goi trong 0-setup.
mo_lai_ntp() {
    docker exec $CLIENT sh -c \
        "iptables -D OUTPUT -p udp --dport 123 -j DROP 2>/dev/null; true" >/dev/null 2>&1
    return 0
}

# ==============================================================================
# PHAN 2 — DOC TRANG THAI
#
# ⚠️ MOI HAM DUOI DAY PHAI LUON THOAT VOI MA 0.
#    Cac kich ban chay duoi `set -e`; mot `grep`/`curl` that bai (chuyen BINH
#    THUONG khi dang co benh) se giet script giua chung neu khong nuot ma loi.
# ==============================================================================

# ------------------------------------------------------------------------------
# Chay mot lenh TRONG container client, co ap dong ho gia neu GIO_GIA duoc dat.
#
# faketime chen qua LD_PRELOAD nen no lua CA `curl`, CA `openssl`, CA `date` —
# tuc la ta do duoc dung cai dong ho ma tien trinh do nhin thay, khong phai suy
# doan. Va no khong dung mot mili giay nao vao dong ho that cua may hoc vien.
#
# ⚠️ Lenh duoc dua vao qua STDIN chu khong qua `sh -c "..."`.
#    Cac lenh o duoi chua san nhay don — `sed -n 's/.../p'`, `-w '%{http_code}'`.
#    Neu boc them mot lop `sh -c '...'` nua thi nhay don long nhau, shell cat
#    chuoi sai cho, va lenh chay ra ket qua RONG. Loi do khong bao gio nem
#    exception: no chi lam moi o hien "(khong bat tay duoc)" va ca kich ban im
#    lang day sai. Dua qua stdin thi khong con lop quoting nao de hong.
# ------------------------------------------------------------------------------
_trong_client() {
    if [ -n "$GIO_GIA" ]; then
        printf '%s' "$1" | docker exec -i $CLIENT faketime "$GIO_GIA" sh 2>/dev/null || true
    else
        printf '%s' "$1" | docker exec -i $CLIENT sh 2>/dev/null || true
    fi
    return 0
}

# Dong ho MA TIEN TRINH NHIN THAY (da tinh ca GIO_GIA).
gio_client()   { _trong_client "date '+%Y-%m-%d %H:%M:%S'";  return 0; }
epoch_client() { _trong_client "date -u +%s";                   return 0; }

# Dong ho phia server. Ngoai doi lay bang `ssh server date`, hoac doc header
# `Date:` cua bat ky phan hoi HTTP nao — HTTP khong can TLS nen van doc duoc
# ngay ca khi TLS dang hong.
gio_server()   { docker exec $WEB date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true; return 0; }
epoch_server() { docker exec $WEB date -u +%s 2>/dev/null || true; return 0; }

# Chenh lech dong ho client so voi server, tinh bang giay (co the am).
lech_giay() {
    local c s
    c=$(epoch_client); s=$(epoch_server)
    if [ -z "$c" ] || [ -z "$s" ]; then echo 0; return 0; fi
    echo $(( c - s ))
    return 0
}

# Doi so giay thanh chuoi de doc: "+8 nam 118 ngay" / "-6 nam 246 ngay" / "0 giay".
lech_doc_duoc() {
    local s=${1:-0} dau abs nam ngay gio
    if [ "$s" -lt 0 ]; then dau="-"; abs=$(( -s )); else dau="+"; abs=$s; fi
    if [ "$abs" -lt 60 ]; then echo "${dau}${abs} giây"; return 0; fi
    nam=$(( abs / 31536000 )); abs=$(( abs % 31536000 ))
    ngay=$(( abs / 86400 ));   abs=$(( abs % 86400 ))
    gio=$(( abs / 3600 ))
    local out=""
    [ "$nam"  -gt 0 ] && out="$out$nam năm "
    [ "$ngay" -gt 0 ] && out="$out$ngay ngày "
    [ -z "$out" ] && out="$gio giờ"
    echo "${dau}${out% }"
    return 0
}

# ------------------------------------------------------------------------------
# GOC NHIN 1 — OpenSSL. Ky thuat vien go `openssl s_client` de "kiem tra cert".
#
# ⚠️ CAI BAY: s_client MAC DINH KHONG kiem tra ten mien. No chi kiem chuoi tin
#    cay va thoi han. Cert dung han nhung cap cho ten mien KHAC van cho ra
#    "Verify return code: 0 (ok)" — trong khi trinh duyet tu choi thang thung.
#    Muon s_client kiem tra ten mien phai them -verify_hostname. Xem MR2.
# ------------------------------------------------------------------------------
verify_openssl() {
    local host="${1:-$TEN}" extra="${2:-}"
    local v
    v=$(_trong_client "echo | openssl s_client -connect $IP_WEB:443 -servername $host -CAfile $CA $extra 2>&1 | sed -n 's/.*Verify return code: //p' | head -1")
    echo "${v:-(không bắt tay được)}"
    return 0
}

# ------------------------------------------------------------------------------
# GOC NHIN 2 — curl, tuc la goc nhin cua UNG DUNG THAT.
# In 3 truong ngan cach boi "|":  http_code | curl_exit | dong loi dau tien
# Dung "|" chu khong dung khoang trang: thong bao loi cua curl CO khoang trang,
# tach theo khoang trang se lam lech cot.
# ------------------------------------------------------------------------------
curl_thu() {
    local host="${1:-$TEN}"
    _trong_client "curl -sS -o /dev/null --connect-timeout 3 --max-time 8 -w '%{http_code}' 'https://$host/' 2>/tmp/e; printf '|%s|' \$?; head -1 /tmp/e | tr -d '\r\n'"
    return 0
}

# ------------------------------------------------------------------------------
# Cert DOC TU DAY (khong doc file tren dia).
#
# Vi sao phai doc tu day? Vi cau hoi that su la "server DANG serve cai gi",
# khong phai "file nao dang nam trong thu muc". Hai thu do lech nhau moi khi ai
# do sua cau hinh ma quen reload — mot trong nhung nguyen nhan pho bien nhat cua
# "toi gia han cert roi ma van bao het han".
# ------------------------------------------------------------------------------
_pem_tu_day() {
    local host="${1:-$TEN}"
    docker exec $CLIENT sh -c \
        "echo | openssl s_client -connect $IP_WEB:443 -servername $host 2>/dev/null | sed -n '/BEGIN CERT/,/END CERT/p'" \
        2>/dev/null || true
    return 0
}

cert_tren_day() {
    local pem; pem=$(_pem_tu_day "${1:-$TEN}")
    [ -z "$pem" ] && return 0
    echo "$pem" | docker exec -i $CLIENT sh -c \
        "openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null" 2>/dev/null || true
    return 0
}

# Mot truong cu the cua cert tren day: han_cert notBefore | notAfter | subject | issuer
han_cert() {
    local pem; pem=$(_pem_tu_day "$TEN")
    [ -z "$pem" ] && { echo "(không lấy được)"; return 0; }
    echo "$pem" | docker exec -i $CLIENT sh -c "openssl x509 -noout -dates 2>/dev/null" \
        | sed -n "s/^$1=//p" | head -1
    return 0
}

san_cert() {
    local pem; pem=$(_pem_tu_day "${1:-$TEN}")
    [ -z "$pem" ] && { echo "(không lấy được)"; return 0; }
    echo "$pem" | docker exec -i $CLIENT sh -c "openssl x509 -noout -ext subjectAltName 2>/dev/null" \
        | grep -o 'DNS:[^,]*' | paste -sd',' - 2>/dev/null
    return 0
}

# ------------------------------------------------------------------------------
# NGUON GIO THAT — hoi NTP server cua lab.
#
# `chronyd -Q` CHI DOC: no do lech gio roi in ra, KHONG dat lai dong ho. Nho vay
# khong can CAP_SYS_TIME va khong bao gio dung toi dong ho may that cua hoc vien.
# Ngoai doi lenh tuong duong la `chronyc tracking` hoac `ntpdate -q <server>`.
# ------------------------------------------------------------------------------
hoi_gio_ntp() {
    docker exec $CLIENT sh -c \
        "timeout 12 chronyd -Q -t 8 'server $IP_NTP iburst' 2>&1 | grep -Ev '^$'" \
        2>/dev/null || true
    return 0
}

# Chi lay dong ket luan: offset do duoc, hoac thong bao that bai.
ntp_ket_qua() {
    local out; out=$(hoi_gio_ntp)
    local ok
    ok=$(echo "$out" | sed -n 's/.*System clock wrong by \(.*\)$/lệch \1/p' | head -1)
    if [ -n "$ok" ]; then echo "$ok"; return 0; fi
    if echo "$out" | grep -qi "No suitable source"; then
        echo "THẤT BẠI — không hỏi được nguồn giờ nào (UDP 123 bị chặn?)"
        return 0
    fi
    echo "${out:-(không có phản hồi)}" | tail -1
    return 0
}

tcp_thu() {
    if docker exec $CLIENT sh -c "nc -z -w2 $IP_WEB 443" >/dev/null 2>&1; then
        echo "MO"
    else
        echo "DONG"
    fi
    return 0
}

buoc() { echo ""; echo "=========================================="; echo "🩺 $*"; echo "=========================================="; }

# ==============================================================================
# PHAN 3 — IN CHU KY CUA CA BENH
#
# Moi kich ban ket thuc bang in_chu_ky. Sau chi so duoi day tao thanh mot "van
# tay" duy nhat cho tung ca benh. Hoc thuoc bang van tay la hoc xong tap 9.
# ==============================================================================
in_chu_ky() {
    local host="${1:-$TEN}"
    local gc gs l ld nb na san v code rc msg tcp

    tcp=$(tcp_thu)
    gc=$(gio_client); gs=$(gio_server)
    l=$(lech_giay);   ld=$(lech_doc_duoc "$l")
    nb=$(han_cert notBefore); na=$(han_cert notAfter)
    san=$(san_cert "$host")
    v=$(verify_openssl "$host")
    IFS='|' read -r code rc msg <<<"$(curl_thu "$host")"

    [ "$tcp" = "MO" ] && tcp="MỞ" || tcp="ĐÓNG"

    echo "  TCP 443            : $tcp"
    echo "  Đồng hồ CLIENT     : ${gc:-?} GMT+7 <- đồng hồ mà tiến trình NHÌN THẤY"
    echo "  Đồng hồ SERVER     : ${gs:-?} GMT+7 <- sự thật để đối chiếu"
    echo "  LỆCH GIỜ           : $ld   <- chỉ số quan trọng nhất của cả tập"
    echo "  Cert đặt trong conf: $(cert_dang_dat).crt"
    echo "  Cert đọc TỪ DÂY    : notBefore=${nb:-?}"
    echo "                       notAfter =${na:-?}"
    echo "                       SAN      =${san:-(không có)}   (đang hỏi tên: $host)"
    echo "  openssl verify     : $v   <- KHÔNG kiểm tra tên miền"
    echo "  curl (ứng dụng)    : http=${code} exit=${rc}"
    echo "                       ${msg:-(không có thông báo lỗi)}"
    echo "  ---"
    echo "  KẾT LUẬN           : $(ket_luan "$v" "$l" "$rc" "$msg")"
    return 0
}

# ------------------------------------------------------------------------------
# LUAT CHAN DOAN — dung mot ma verify KHONG du de ket luan.
#
# Bang su that cua ca tap gom trong ham nay: ma 10 ("certificate has expired")
# xuat hien o CA HAI ca benh trai nguoc nhau. Thu tach chung ra chi co mot: doi
# chieu ma verify voi DO LECH GIO. Do la ly do lech_giay phai duoc do bang mot
# nguon KHAC dong ho cua chinh may dang bao loi.
# ------------------------------------------------------------------------------
ket_luan() {
    local v="$1" lech="$2" rc="$3" msg="$4"
    local abs=$lech; [ "$abs" -lt 0 ] && abs=$(( -abs ))
    # Duoi 1 gio thi coi nhu hai dong ho khop nhau (du rong de khong bao dong gia).
    local khop=0; [ "$abs" -lt 3600 ] && khop=1

    case "$v" in
        0\ \(ok\)*)
            if [ "$rc" = "0" ]; then
                echo "KHỎE — chuỗi tin cậy đúng, còn hạn, tên miền khớp."
            elif echo "$msg" | grep -qi "subject name\|subjectAltName\|common name"; then
                echo "SAI TÊN MIỀN. Cert còn hạn và CA tin được, nhưng KHÔNG cấp cho tên đang hỏi."
                echo "                       -> Đây là lý do openssl báo 'ok' mà curl vẫn từ chối:"
                echo "                          s_client mặc định KHÔNG kiểm tra tên miền."
            else
                echo "Cert hợp lệ nhưng ứng dụng vẫn lỗi (exit $rc) — đọc thông báo curl ở trên."
            fi ;;
        10*)   # certificate has expired
            if [ "$khop" = "1" ]; then
                echo "CERT ĐÃ HẾT HẠN THẬT. Hai đồng hồ khớp nhau, nên notAfter là sự thật."
                echo "                       -> Thủ phạm: SERVER (quên gia hạn). Chữa: thay cert mới."
            else
                echo "CERT VẪN CÒN HẠN — ĐỒNG HỒ CLIENT chạy nhanh $(lech_doc_duoc "$lech")."
                echo "                       -> Thủ phạm: CLIENT. Chữa: đồng bộ NTP, đừng thay cert."
            fi ;;
        9*)    # certificate is not yet valid
            if [ "$khop" = "1" ]; then
                echo "CERT CHƯA ĐẾN NGÀY HIỆU LỰC. Hai đồng hồ khớp, notBefore là sự thật."
                echo "                       -> Thủ phạm: SERVER/CA (cấp nhầm ngày). Chờ, hoặc cấp lại."
            else
                echo "CERT VẪN HỢP LỆ — ĐỒNG HỒ CLIENT tụt hậu $(lech_doc_duoc "$lech")."
                echo "                       -> Thủ phạm: CLIENT (hết pin CMOS / mất NTP). Chữa: đồng bộ NTP."
            fi ;;
        18*|19*|20*|21*)
            echo "KHÔNG TIN ĐƯỢC NGƯỜI KÝ. Đây là lỗi CHUỖI TIN CẬY, không liên quan gì đến giờ."
            echo "                       -> Trình duyệt báo ERR_CERT_AUTHORITY_INVALID, KHÔNG phải DATE_INVALID." ;;
        *)
            echo "Chưa khớp luật nào — đọc kỹ mã verify và thông báo curl ở trên." ;;
    esac
    return 0
}
