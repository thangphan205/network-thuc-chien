#!/usr/bin/env bash
# ==============================================================================
# Hang so & ham dung chung cho cac script cua tap 6
#
#   172.28.6.0/24 — mot LAN phang, khong router. Ca benh cua tap nay nam o
#   TANG 7 (phan giai ten), nen moi thu o L2/L3/L4 deu phai dung tuyet doi de
#   khong ai do lai cho duong truyen.
# ==============================================================================
DNS=lab06-dns
CLIENT=lab06-client
WEB=lab06-web
WEB_CU=lab06-web-cu

IP_DNS=172.28.6.53
IP_WEB=172.28.6.10
IP_WEB_CU=172.28.6.11
IP_CLIENT=172.28.6.20
IP_MA=172.28.6.99          # IP khong co may nao — dung cho KB2 va MR4 phan 2

TEN=web.lab.local          # ten mien chinh cua lab
ZONE=/etc/dnsmasq/zone-hosts
CONF=/etc/dnsmasq/dnsmasq.conf
LOG_DNS=/var/log/dnsmasq.log

# ==============================================================================
# PHAN 1 — DIEU KHIEN LAB
# ==============================================================================

# ------------------------------------------------------------------------------
# Ghi de /etc/resolv.conf trong client.
#
# Vi sao dung `>` chu khong `sed -i`? Docker bind-mount /etc/resolv.conf tu mot
# file tren host. `>` cat ngan file TAI CHO (giu nguyen inode) nen ghi duoc;
# `sed -i` tao file moi roi rename -> "Device or resource busy".
# ------------------------------------------------------------------------------
dat_resolv() {
    docker exec -i $CLIENT sh -c "cat > /etc/resolv.conf" <<EOF
nameserver $1
search lab.local
options ndots:1 timeout:1 attempts:2
EOF
}

nap_lai_dns() { docker exec $DNS dns-start >/dev/null 2>&1 || true; }

# ------------------------------------------------------------------------------
# Sua /etc/hosts trong client.
#
# ⚠️ /etc/hosts cung bi Docker bind-mount tu host giong /etc/resolv.conf, nen
#    `sed -i` that bai voi "Device or resource busy" (no ghi file tam roi rename).
#    Ma loi do bi nuot mat trong `|| true` -> 0-setup TUONG la da don sach trong
#    khi dong xau van con, va KB3 ro ri sang moi kich ban sau no. Phai ghi TAI CHO.
# ------------------------------------------------------------------------------
xoa_hosts_lab() {
    docker exec $CLIENT sh -c "grep -v '[[:space:]]$TEN\$' /etc/hosts > /tmp/h; cat /tmp/h > /etc/hosts"
}
them_hosts() {
    xoa_hosts_lab
    docker exec $CLIENT sh -c "printf '%s %s\n' '$1' '$TEN' >> /etc/hosts"
}

# Sua mot ban ghi A trong zone roi nap lai. vd: doi_ban_ghi web.lab.local 172.28.6.11
doi_ban_ghi() {
    local ten="$1" ip="$2" ngan="${1%%.*}"
    docker exec $DNS sh -c "grep -v '[[:space:]]$ten[[:space:]]' $ZONE > /tmp/z 2>/dev/null; printf '%s   %s  %s\n' '$ip' '$ten' '$ngan' >> /tmp/z; cp /tmp/z $ZONE"
    nap_lai_dns
}

# ------------------------------------------------------------------------------
# GOC NHIN PHIA SERVER.
#
# dnsmasq duoc khoi dong bang `docker exec` (xem dns/dns-start) nen no KHONG
# phai PID 1 — `docker compose logs dns` bat duoc SO KHONG dong. Log nam trong
# file cua container. Day la cong cu tach KB2 (log TRONG: goi chua tung toi noi)
# khoi MR3 (log CO query: goi toi noi, server moi la ben khong tra loi duoc).
# ------------------------------------------------------------------------------
xoa_log_dns() { docker exec $DNS sh -c ": > $LOG_DNS" 2>/dev/null || true; }
log_dns()     { docker exec $DNS tail -n "${1:-15}" $LOG_DNS 2>/dev/null || true; }

# grep -c thoat voi ma 1 khi dem duoc 0 — phai nuot ma loi do, neu khong
# `set -e` trong kich ban se giet script ngay tai day.
dem_query_o_server() {
    docker exec $DNS sh -c "grep -c 'query\[' $LOG_DNS 2>/dev/null; true" 2>/dev/null | head -1 | tr -d '\r'
    return 0
}

# ==============================================================================
# PHAN 2 — DOC TRANG THAI
#
# ⚠️ MOI HAM DUOI DAY PHAI LUON THOAT VOI MA 0.
#    Cac kich ban chay duoi `set -e`; mot `grep` khong khop (chuyen binh thuong
#    khi dang co benh) se giet script giua chung neu khong nuot ma loi.
# ==============================================================================

# ------------------------------------------------------------------------------
# Chay dig DUNG MOT LAN roi tra ve toan bo ket qua kem dong ho ngoai.
#
# ⚠️ Vi sao bat buoc phai gop lam MOT lan? Linux gioi han toc do phat goi ICMP
#    unreachable (net.ipv4.icmp_ratelimit, mac dinh 1 goi/giay). Neu ta ban 4-5
#    lan dig lien tiep vao mot cong DA DONG, goi ICMP thu 2 tro di bi kernel
#    chan lai — va "connection refused" bong bien thanh "timed out". Ca benh
#    MR1 se doi mat thanh KB2 mot cach ngau nhien. Mot lan dig, doc moi thu tu
#    do ra: vua nhanh vua tat dinh.
# ------------------------------------------------------------------------------
dig_full() {
    docker exec $CLIENT sh -c \
        "S=\$(date +%s%N); dig ${1:-$TEN} 2>&1; E=\$(date +%s%N); echo \";; WALL: \$(( (E-S)/1000000 )) msec\"" \
        2>/dev/null || true
    return 0
}

_lay()      { echo "$1" | sed -n "$2" | head -1; }
dig_status_tu()   { local v; v=$(_lay "$1" 's/.*status: \([A-Z]*\).*/\1/p'); echo "${v:-KHÔNG-TRẢ-LỜI}"; }
dig_qtime_tu()    { _lay "$1" 's/^;; Query time: \([0-9]*\) msec.*/\1/p'; }
dig_wall_tu()     { _lay "$1" 's/^;; WALL: \([0-9]*\) msec.*/\1/p'; }
dig_loi_tu()      { echo "$1" | grep -m1 -E 'communications error|network unreachable' | sed 's/^;; *//' || true; }
# IP trong ANSWER SECTION. Chi lay ban ghi A, bo qua CNAME.
dig_ip_tu()       { echo "$1" | awk '$4=="A" && $5 ~ /^[0-9.]+$/ {print $5; exit}' || true; }

# IP ma UNG DUNG that su dung: di qua NSS (/etc/hosts -> nscd -> DNS).
# Khac biet giua ham nay va dig_ip_tu chinh la o benh cua KB3 va MR5.
ip_theo_nss() { docker exec $CLIENT getent hosts "${1:-$TEN}" 2>/dev/null | awk '{print $1}' | head -1 || true; return 0; }

# Goi HTTP that. In 3 truong ngan cach boi "|": http_code | ip_da_ket_noi | exit
# Dung "|" chu khong dung khoang trang: khi curl that bai %{remote_ip} rong ->
# tach theo khoang trang se lam lech cot va bao cao sai ma loi.
curl_thu() {
    docker exec $CLIENT sh -c \
      "curl -s -o /dev/null --connect-timeout 3 --max-time 5 -w '%{http_code}|%{remote_ip}' 'http://${1:-$TEN}/' 2>/dev/null; echo \"|\$?\"" \
      2>/dev/null || true
    return 0
}

# Tieu de trang -> biet dang noi chuyen voi may NAO.
noi_dung_trang() {
    docker exec $CLIENT sh -c "curl -s --connect-timeout 3 --max-time 5 'http://${1:-$TEN}/' 2>/dev/null | sed -n 's/.*<h1>\(.*\)<\/h1>.*/\1/p' | head -1" 2>/dev/null || true
    return 0
}

# Cac ham tien loi cho kich ban (moi ham = 1 lan dig).
ip_theo_dig() { dig_ip_tu "$(dig_full "${1:-$TEN}")"; return 0; }

buoc() { echo ""; echo "=========================================="; echo "🩺 $*"; echo "=========================================="; }

# ------------------------------------------------------------------------------
# IN CHU KY CUA CA BENH — moi kich ban ket thuc bang ham nay.
#
# 7 chi so duoi day tao thanh mot "van tay" DUY NHAT cho tung ca benh.
# Hoc thuoc bang van tay nay la hoc xong tap 6.
# ------------------------------------------------------------------------------
in_chu_ky() {
    local ten="${1:-$TEN}"
    local raw st qt wall d n page code rip rc q
    raw=$(dig_full "$ten")
    st=$(dig_status_tu "$raw"); qt=$(dig_qtime_tu "$raw"); wall=$(dig_wall_tu "$raw")
    d=$(dig_ip_tu "$raw");      n=$(ip_theo_nss "$ten")
    IFS='|' read -r code rip rc <<<"$(curl_thu "$ten")"
    page=$(noi_dung_trang "$ten")
    q=$(dem_query_o_server)

    echo "  dig status      : ${st}"
    if [ "$st" = "KHÔNG-TRẢ-LỜI" ]; then
        echo "  dig báo lỗi     : $(dig_loi_tu "$raw")"
        echo "  dig bỏ cuộc sau : ${wall:-?} ms   <- đồng hồ ngoài; KHÔNG có câu trả lời nào"
    else
        echo "  dig Query time  : ${qt:-?} ms   <- server đáp trong bao lâu"
    fi
    echo "  IP theo dig     : ${d:-(không ra)}       <- sự thật phía DNS server"
    echo "  IP theo NSS/app : ${n:-(không ra)}       <- IP ứng dụng THẬT SỰ dùng"
    echo "  curl            : http_code=${code} exit=${rc} kết nối tới ${rip:-(không tới đâu)}"
    echo "  trang nhận được : ${page:-(không có)}"
    echo "  query tới server: ${q}   <- 0 nghĩa là gói tin CHƯA TỪNG tới được DNS server"
}
