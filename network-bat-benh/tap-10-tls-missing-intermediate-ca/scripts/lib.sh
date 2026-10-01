#!/usr/bin/env bash
# ==============================================================================
# Hang so & ham dung chung cho cac script cua tap 10
#
#   172.28.10.0/24 — mot LAN phang, khong router. Moi thu o L2/L3/L4 deu dung
#   tuyet doi. Ca benh nam o TANG 5/6: khau XAY DUNG VA XAC THUC CHUOI TIN CAY.
#
# TU TUONG CUA CA TAP:
#   Client khong xac thuc MOT cert. No xac thuc mot DUONG DI:
#
#        [leaf]  --(1)-->  [intermediate]  --(2)-->  [root trong trust store]
#
#   Doan (1) do SERVER chiu trach nhiem: server phai GUI KEM cert intermediate.
#   Doan (2) do CLIENT chiu trach nhiem: may phai CO SAN root trong trust store.
#
#   Dut doan nao cung ra DUNG MOT dong chu:
#        verify error:num=20:unable to get local issuer certificate
#
#   Thu duy nhat tach duoc hai ca benh trai nguoc nay la con so DEPTH:
#        depth=0  ->  dut o doan (1)  ->  SERVER sai   ->  sua cau hinh nginx
#        depth=1  ->  dut o doan (2)  ->  CLIENT sai   ->  cai CA vao trust store
#
#   Vi vay cau hoi dau tien khi debug chuoi tin cay khong bao gio la
#   "cert co van de gi?" ma la: "no dut o depth may?"
# ==============================================================================
WEB=lab10-web-server
CLIENT=lab10-client
CLIENT_NODE=lab10-client-node   # may Debian + image Node chinh thuc, dung cho MR7
AIA=lab10-aia

IP_WEB=172.28.10.10
IP_CLIENT=172.28.10.20
IP_CLIENT_NODE=172.28.10.21
IP_AIA=172.28.10.30

TEN=app.chain.local        # ten mien chinh, khop SAN cua moi leaf trong lab
TEN_AIA=aia.lab.local      # may chu phuc vu cert trung gian cho MR4
PORT_HOST=8444             # cong publish ra may that (443 trong lab-net)

# Trust store CUA MAY, khong phai mot file --cacert dinh kem.
# Ca benh KB3 song bang chinh cho nay: neu lab dinh --cacert vao moi lenh thi
# "thieu CA trong trust store" khong bao gio xay ra duoc.
TRUST=/etc/ssl/certs/ca-certificates.crt
ROOT_TRONG_CLIENT=/etc/ssl/lab/rootCA.crt
ROOT_DA_CAI=/usr/local/share/ca-certificates/lab10-root.crt

NGINX_CONF=nginx/nginx.conf

# ==============================================================================
# PHAN 1 — DIEU KHIEN LAB
# ==============================================================================

# ------------------------------------------------------------------------------
# Doi CHUOI ma nginx gui ra day.   dat_chuoi good | thieu-int | thua-root | ...
#
# Vi sao `restart` chu khong `nginx -s reload`?
#   nginx.conf duoc bind-mount tu may that. Tren Docker Desktop (macOS/Windows)
#   lop chia se file co the tra ve NOI DUNG CU cho tien trinh dang chay, nen
#   reload doi khi nap lai dung cai cu — loi chi hien tren may cua mot vai hoc
#   vien va cuc ky kho lan. restart tao tien trinh moi, doc lai tu dau.
#
# ⚠️ Ham nay KHONG duoc `set -e` giet khi nginx tu choi khoi dong: MR1 (chuoi
#    dao nguoc) lam nginx chet CO CHU DICH — do la chu ky cua ca benh.
# ------------------------------------------------------------------------------
dat_chuoi() {
    cp "nginx/conf/$1.conf" "$NGINX_CONF"
    docker compose restart web-server >/dev/null 2>&1 || true
    cho_web_san_sang
    return 0
}

# ------------------------------------------------------------------------------
# Doi file cau hinh NHUNG KHONG reload — dung cho MR8.
#
# Day la cach tai hien mot trong nhung su co pho bien nhat ngoai doi: "toi sua
# roi ma van loi". File tren dia da dung, tien trinh dang chay van giu cau hinh
# cu trong bo nho. Moi cong cu doc FILE deu bao OK; moi client doc DAY deu bao
# hong. Hai ben cai nhau ca buoi chieu.
# ------------------------------------------------------------------------------
dat_chuoi_khong_reload() {
    cp "nginx/conf/$1.conf" "$NGINX_CONF"
    return 0
}

# nginx can vai tram ms de mo lai cong 443. Khong cho thi lenh test ngay sau do
# se bao "Connection refused" va hoc vien tuong day la trieu chung cua ca benh.
cho_web_san_sang() {
    local i
    for i in $(seq 1 25); do
        if docker exec $CLIENT sh -c "timeout 1 nc -z $IP_WEB 443" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.3
    done
    return 0
}

nginx_song() {
    if [ "$(docker inspect -f '{{.State.Running}}' $WEB 2>/dev/null)" = "true" ]; then
        echo "ĐANG CHẠY"
    else
        echo "ĐÃ CHẾT"
    fi
    return 0
}

# Vi sao nginx chet — doc thang tu log cua no.
nginx_ly_do_chet() {
    docker logs --tail 30 $WEB 2>&1 \
        | grep -iE 'emerg|mismatch|PEM|SSL_CTX|cannot load' | tail -3 || true
    return 0
}

# Chuoi dang duoc cau hinh (doc tu file conf, khong doc tu day).
chuoi_dang_dat() {
    sed -n 's#.*ssl_certificate  *[^ ]*/\([A-Za-z0-9_-]*\.crt\);#\1#p' "$NGINX_CONF" 2>/dev/null | head -1
    return 0
}

# ------------------------------------------------------------------------------
# TRUST STORE CUA CLIENT — hai ham nay la toan bo ca benh KB3.
#
# Ngoai doi day chinh la: image container base khong co CA noi bo; may moi cai
# lai chua import CA cua cong ty; JVM co truststore RIENG (cacerts) ma khong ai
# nho cap nhat.
# ------------------------------------------------------------------------------
cai_root() {
    docker exec $CLIENT sh -c \
        "cp $ROOT_TRONG_CLIENT $ROOT_DA_CAI && update-ca-certificates" >/dev/null 2>&1 || true
    return 0
}

# Cai root vao trust store HE DIEU HANH cua may Debian (MR7).
# Chu y: no cai vao dung cho ma `update-ca-certificates` cua Debian doc — va
# curl se thay ngay. Viec Node co thay hay khong la chuyen HOAN TOAN KHAC.
cai_root_node() {
    docker exec $CLIENT_NODE sh -c \
        "mkdir -p /usr/local/share/ca-certificates && cp $ROOT_TRONG_CLIENT /usr/local/share/ca-certificates/lab10-root.crt && update-ca-certificates" \
        >/dev/null 2>&1 || true
    return 0
}

go_root() {
    docker exec $CLIENT sh -c \
        "rm -f $ROOT_DA_CAI && update-ca-certificates --fresh" >/dev/null 2>&1 || true
    return 0
}

# Trust store cua client CO root cua lab hay khong?
co_root() {
    if docker exec $CLIENT sh -c \
        "grep -q -F \"\$(openssl x509 -in $ROOT_TRONG_CLIENT -outform PEM | sed -n '2p')\" $TRUST" \
        >/dev/null 2>&1; then
        echo "CÓ root của lab"
    else
        echo "KHÔNG có root của lab"
    fi
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
# Chay mot lenh TRONG container client.
#
# ⚠️ Lenh duoc dua vao qua STDIN chu khong qua `sh -c "..."`.
#    Cac lenh o duoi chua san nhay don — `sed -n 's/.../p'`, `-w '%{http_code}'`.
#    Neu boc them mot lop `sh -c '...'` nua thi nhay don long nhau, shell cat
#    chuoi sai cho, va lenh chay ra ket qua RONG. Loi do khong bao gio nem
#    exception: no chi lam moi o hien "(không bắt tay được)" va ca kich ban im
#    lang day sai. Dua qua stdin thi khong con lop quoting nao de hong.
# ------------------------------------------------------------------------------
_trong_client() {
    printf '%s' "$1" | docker exec -i $CLIENT sh 2>/dev/null || true
    return 0
}

# Toan bo output cua mot lan bat tay. Cac ham duoi deu cat tu day ra, de mot
# kich ban chi mo MOT ket noi TLS thay vi bon nam ket noi (khi dang co benh moi
# ket noi deu phai cho het timeout).
_bat_tay() {
    _trong_client "echo | timeout 10 openssl s_client -connect $IP_WEB:443 -servername ${1:-$TEN} -CAfile $TRUST -showcerts 2>&1"
    return 0
}

# ------------------------------------------------------------------------------
# ⭐ HAM QUAN TRONG NHAT CUA TAP — in "ma|depth|thong bao".
#
# openssl in ra hai dong roi nhau:
#     depth=1 CN = Lab10 Intermediate CA      <- cert dang xet
#     verify error:num=20:unable to get local issuer certificate
# Con so depth nam o dong TRUOC dong loi. Doc rieng dong loi thi mat sach thong
# tin phan biet — va do dung la ly do hau het moi nguoi debug nham tap nay.
# ------------------------------------------------------------------------------
verify_chi_tiet() {
    local raw="${1:-}"
    [ -z "$raw" ] && raw=$(_bat_tay)
    [ -z "$raw" ] && { echo "-|-|(không bắt tay được)"; return 0; }

    local kq
    kq=$(echo "$raw" | awk '
        /^depth=/          { d = $0; sub(/^depth=/, "", d); sub(/ .*/, "", d) }
        /^verify error:num=/ && !got {
            n = $0; sub(/^verify error:num=/, "", n)
            i = index(n, ":")
            printf "%s|%s|%s\n", substr(n, 1, i-1), d, substr(n, i+1)
            got = 1
        }')
    if [ -n "$kq" ]; then echo "$kq"; return 0; fi

    # Khong co dong loi nao => chuoi hop le.
    if echo "$raw" | grep -q "Verify return code: 0"; then
        echo "0|-|ok"
    else
        echo "-|-|(không đọc được kết quả verify)"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# CHUOI SERVER GUI RA DAY — khong doc file tren dia.
#
# Cau hoi that su la "server DANG gui nhung gi", khong phai "file nao dang nam
# trong thu muc". Hai thu do lech nhau moi khi ai do sua cau hinh ma quen reload
# — mot trong nhung nguyen nhan pho bien nhat cua "toi sua roi ma van loi".
# ------------------------------------------------------------------------------
chuoi_gui_ra() {
    local raw="${1:-}"
    [ -z "$raw" ] && raw=$(_bat_tay)
    echo "$raw" | awk '
        /^ *[0-9]+ s:/ { n=$0; sub(/^ */, "", n); print "   " n }
        /^ *  *i:/     { n=$0; sub(/^ */, "", n); print "     " n }'
    return 0
}

# ------------------------------------------------------------------------------
# ⭐ KIEM TRA CAC MAT XICH CO KHOP NHAU KHONG.
#
# Phep DEM cert KHONG du de ket luan server da lam dung phan viec cua no. Server
# hoan toan co the gui 2 cert ma van sai — neu cert thu hai la intermediate cua
# MOT CA KHAC (copy nham ca-bundle). Luc do so cert = 2, ma verify van 20 depth 0.
#
# Quy tac dung: issuer cua cert N phai TRUNG subject cua cert N+1.
# Ham nay doc cac dong `s:`/`i:` cua s_client roi ghep tung cap.
# ------------------------------------------------------------------------------
kiem_mat_xich() {
    local raw="${1:-}"
    [ -z "$raw" ] && raw=$(_bat_tay)
    echo "$raw" | awk '
        # ⚠️ Phai dat c=0 o BEGIN. Trong awk, mot bien CHUA GAN dung lam chi so
        #    mang se cho ra khoa "" (chuoi rong) chu KHONG phai 0 — nen cap dau
        #    tien se nam o iss[""] va vong lap o END khong bao gio thay no.
        BEGIN { c = 0 }
        /^ *[0-9]+ s:/ { n=$0; sub(/^ *[0-9]+ s:/, "", n); subj[c] = n }
        /^ *i:/        { n=$0; sub(/^ *i:/, "", n);        iss[c]  = n; c++ }
        END {
            if (c == 0) { print "     (khong doc duoc chuoi)"; exit }
            for (k = 0; k < c - 1; k++) {
                if (iss[k] == subj[k+1])
                    printf "     ✅ tầng %d ký bởi tầng %d  — khớp\n", k, k+1
                else {
                    printf "     ❌ tầng %d nối KHÔNG tới tầng %d — ĐỨT MẮT XÍCH\n", k, k+1
                    printf "        tầng %d cần người ký : %s\n", k, iss[k]
                    printf "        tầng %d thực tế là   : %s\n", k+1, subj[k+1]
                }
            }
            printf "     ↑ tầng %d (trên cùng) phải nối được lên TRUST STORE: %s\n", c-1, iss[c-1]
        }'
    return 0
}

so_cert_gui() {
    local raw="${1:-}"
    [ -z "$raw" ] && raw=$(_bat_tay)
    echo "$raw" | grep -c '^-----BEGIN CERTIFICATE-----' || true
    return 0
}

# URL AIA nam trong cert cua server (neu co). Day la thu trinh duyet doc, con
# curl thi khong.
aia_url() {
    local raw="${1:-}"
    [ -z "$raw" ] && raw=$(_bat_tay)
    printf '%s' "$raw" | sed -n '/BEGIN CERT/,/END CERT/p' \
        | docker exec -i $CLIENT sh -c "openssl x509 -noout -text 2>/dev/null" \
        | sed -n 's/.*CA Issuers - URI://p' | head -1
    return 0
}

# ------------------------------------------------------------------------------
# GOC NHIN CUA UNG DUNG THAT.
# In 3 truong ngan cach boi "|":  http_code | curl_exit | dong loi dau tien
# Dung "|" chu khong dung khoang trang: thong bao loi cua curl CO khoang trang,
# tach theo khoang trang se lam lech cot.
# ------------------------------------------------------------------------------
curl_thu() {
    local host="${1:-$TEN}"
    _trong_client "curl -sS -o /dev/null --connect-timeout 3 --max-time 8 -w '%{http_code}' 'https://$host/' 2>/tmp/e; printf '|%s|' \$?; head -1 /tmp/e | tr -d '\r\n'"
    return 0
}

tcp_thu() {
    if docker exec $CLIENT sh -c "timeout 2 nc -z $IP_WEB 443" >/dev/null 2>&1; then
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
# tay" duy nhat cho tung ca benh. Hoc thuoc bang van tay la hoc xong tap 10.
# ==============================================================================
in_chu_ky() {
    local host="${1:-$TEN}"
    local raw song tcp n num depth msg code rc cmsg aia

    song=$(nginx_song)
    if [ "$song" = "ĐÃ CHẾT" ]; then
        echo "  nginx              : ❌ ĐÃ CHẾT — không khởi động được"
        echo "  Chuỗi đặt trong conf: $(chuoi_dang_dat)"
        echo "  Lý do (log nginx)  :"
        nginx_ly_do_chet | sed 's/^/     /'
        echo "  ---"
        echo "  KẾT LUẬN           : nginx TỪ CHỐI nạp chuỗi này. Lỗi bị bắt NGAY LÚC"
        echo "                       KHỞI ĐỘNG, chưa hề có client nào kết nối."
        return 0
    fi

    raw=$(_bat_tay "$host")
    tcp=$(tcp_thu)
    [ "$tcp" = "MO" ] && tcp="MỞ" || tcp="ĐÓNG"
    n=$(so_cert_gui "$raw")
    IFS='|' read -r num depth msg <<<"$(verify_chi_tiet "$raw")"
    IFS='|' read -r code rc cmsg <<<"$(curl_thu "$host")"
    aia=$(aia_url "$raw")

    echo "  TCP 443            : $tcp"
    echo "  Chuỗi đặt trong conf: $(chuoi_dang_dat)"
    echo "  Trust store CLIENT : $(co_root)"
    echo "  Số cert GỬI RA DÂY : $n   <- server gửi bao nhiêu tầng chuỗi"
    chuoi_gui_ra "$raw"
    echo "  AIA trong cert     : ${aia:-(không có)}"
    echo "  openssl verify     : num=${num}  DEPTH=${depth}   <- ⭐ số depth là chìa khóa"
    echo "                       ${msg}"
    echo "  curl (ứng dụng)    : http=${code} exit=${rc}"
    echo "                       ${cmsg:-(không có thông báo lỗi)}"
    echo "  ---"
    echo "  KẾT LUẬN           : $(ket_luan "$num" "$depth" "$rc" "$n")"
    return 0
}

# ------------------------------------------------------------------------------
# LUAT CHAN DOAN — mot ma verify KHONG du de ket luan, phai di kem DEPTH.
#
# Bang su that cua ca tap gom trong ham nay: ma 20 xuat hien o CA HAI ca benh
# trai nguoc nhau (server gui thieu / client thieu root). Thu tach chung ra chi
# co mot: con so depth.
# ------------------------------------------------------------------------------
ket_luan() {
    local num="$1" depth="$2" rc="$3" n="$4"
    case "$num" in
        0)
            if [ "$rc" = "0" ]; then
                if [ "${n:-0}" -ge 3 ]; then
                    echo "KHỎE — nhưng chuỗi có $n cert, THỪA. Root đã nằm sẵn trong trust"
                    echo "                       store của client rồi, gửi kèm lại chỉ tốn băng thông mỗi"
                    echo "                       lần bắt tay. Chuẩn là 2 tầng: leaf + intermediate."
                else
                    echo "KHỎE — chuỗi đầy đủ, đúng thứ tự, client nối được lên tới root."
                fi
            else
                echo "Chuỗi hợp lệ nhưng ứng dụng vẫn lỗi (exit $rc) — đọc thông báo curl ở trên."
            fi ;;
        20)
            if [ "$depth" = "0" ] && [ "${n:-0}" -ge 2 ] 2>/dev/null; then
                echo "SERVER GỬI ĐỦ SỐ LƯỢNG NHƯNG SAI NGƯỜI KÝ."
                echo "                       depth=0 + $n cert => server CÓ gửi kèm chuỗi, nhưng cert"
                echo "                       gửi kèm KHÔNG phải người đã ký leaf. Phép đếm cert không"
                echo "                       phát hiện được ca này — phải đối chiếu issuer/subject."
                echo "                       -> Chữa: lấy đúng bundle của CA đã ký leaf. Xem MR5."
            elif [ "$depth" = "0" ]; then
                echo "SERVER GỬI THIẾU INTERMEDIATE."
                echo "                       depth=0 => cert HỎNG là LEAF: không ai bảo lãnh cho nó"
                echo "                       trong những gì server gửi ra. Trust store của client"
                echo "                       KHÔNG có lỗi gì ở đây."
                echo "                       -> Chữa: trỏ ssl_certificate sang file fullchain."
            else
                echo "CLIENT THIẾU ROOT TRONG TRUST STORE."
                echo "                       depth=$depth => server đã gửi ĐỦ chuỗi; cert hỏng nằm ở"
                echo "                       TẦNG TRÊN. Đổi cấu hình server ở đây là chữa nhầm người."
                echo "                       -> Chữa: cài root CA vào trust store của máy/container."
            fi ;;
        10)
            if [ "$depth" = "0" ]; then
                echo "LEAF ĐÃ HẾT HẠN — đây là ca bệnh của TẬP 09, không phải tập 10."
            elif [ "${depth:-0}" -ge 2 ] 2>/dev/null; then
                echo "MỘT CERT Ở TẦNG RẤT CAO (depth=$depth) ĐÃ HẾT HẠN — nhiều khả năng là"
                echo "                       ROOT, hoặc bản cross-sign của nó. Server thường KHÔNG sai ở đây;"
                echo "                       máy này đang thiếu bản root mới trong trust store."
                echo "                       -> Chữa: cập nhật CA bundle của máy/runtime. Xem MR6."
            else
                echo "INTERMEDIATE ĐÃ HẾT HẠN (depth=$depth), LEAF VẪN CÒN HẠN."
                echo "                       Cấp lại leaf sẽ KHÔNG chữa được gì — nó chưa bao giờ hỏng."
                echo "                       -> Chữa: xin CA cấp bản intermediate mới rồi ghép lại chuỗi."
            fi ;;
        21)
            echo "KHÔNG XÁC MINH NỔI CERT ĐẦU TIÊN — chuỗi đứt ngay tầng dưới cùng." ;;
        19)
            echo "CÓ CERT TỰ KÝ TRONG CHUỖI mà trust store không tin. Xem lại root được gửi kèm." ;;
        -)
            echo "Không bắt tay được — kiểm tra container web-server còn sống không." ;;
        *)
            echo "Chưa khớp luật nào — đọc kỹ mã verify và thông báo curl ở trên." ;;
    esac
    return 0
}
