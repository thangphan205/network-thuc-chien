#!/usr/bin/env bash
# ==============================================================================
# Hang so & ham dung chung cho KB3 (tran bang NAT tren Cisco IOL) cua tap 07
#
# TU TUONG CUA CA NAY:
#   Bang NAT co suc chua. Mot may tao qua nhieu flow la chiem het cho, may khac
#   khong tao duoc ban dich moi. Phien cu van song, phien moi chet, va ping
#   cung chet vi ICMP cung can ban dich.
#
# Vi sao gioi han bang "max-entries list LAN" ma khong phai "max-entries 100"?
#   Do tren IOL 17.15.1: ca hai deu chan dung o 100, nhung "max-entries 100" de
#   dong "max entry" luon la used 0, missed 0. "list" moi dem that.
#   "max-entries all-host" hien trong cau hinh nhung KHONG chan: bang len 150.
# ==============================================================================
R1=lab07-cisco-r1
MAY_LOI=lab07-cisco-may-loi
NHAN_VIEN=lab07-cisco-nhan-vien
SERVER=lab07-cisco-server

IP_R1_MGMT=172.28.77.11
IP_MAY_LOI=192.168.1.10
IP_NHAN_VIEN=192.168.2.10
IP_SERVER=203.0.113.10

GIOI_HAN_BANG=100
GIOI_HAN_MAY=20
SO_FLOW=150

buoc() { echo ""; echo "=========================================="; echo "🩺 $*"; echo "=========================================="; }

# ------------------------------------------------------------------------------
# Dung containerlab da cai neu co, khong thi chay ban dong goi trong container.
# ------------------------------------------------------------------------------
clab() {
    if command -v containerlab >/dev/null 2>&1; then
        sudo containerlab "$@"
    else
        docker run --rm --privileged --network host --pid host \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v /run/netns:/run/netns \
            -v /var/lib/docker/containers:/var/lib/docker/containers \
            -v "$PWD:$PWD" -w "$PWD" \
            ghcr.io/srl-labs/clab containerlab "$@"
    fi
}

# ------------------------------------------------------------------------------
# Phai dung session tuong tac: chay lenh qua SSH exec, IOS dong ket noi som va
# output bi cat mat dong cuoi (dung dong nat-limit can doc).
# ------------------------------------------------------------------------------
_ssh_r1() {
    SSH_ASKPASS="$PWD/scripts/askpass.sh" SSH_ASKPASS_REQUIRE=force \
        ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -o ConnectTimeout=8 "admin@$IP_R1_MGMT" 2>&1 | tr -d '\r' || true
}

# r1 "<lenh>" ["<lenh 2>"...]
r1() {
    { sleep 1; echo "terminal length 0"; for c in "$@"; do echo "$c"; sleep 2; done; echo "exit"; sleep 1; } | _ssh_r1
}

# r1_cau_hinh "<dong lenh cau hinh>"...
r1_cau_hinh() {
    { sleep 1; echo "terminal length 0"; echo "configure terminal"
      for c in "$@"; do echo "$c"; sleep 0.3; done
      echo "end"; sleep 1; echo "exit"; sleep 1; } | _ssh_r1 >/dev/null
}

cho_r1_san_sang() {
    local i
    for i in $(seq 1 40); do
        r1 "show clock" | grep -qE '[0-9]+:[0-9]+:[0-9]+\.' && return 0
        sleep 3
    done
    echo "❌ LỖI: R1 không lên sau 2 phút." >&2
    exit 1
}

# ==============================================================================
# DO DAC
# ==============================================================================

thong_ke() {
    r1 "show ip nat statistics" | grep -E 'Total active|max entry|acl |host ' || true
}

# In "used missed" cua dong "acl LAN" hoac "host <ip>"
doc_gioi_han() {
    r1 "show ip nat statistics" |
        sed -n "s/.*$1: max allowed [0-9]*, used \([0-9]*\), missed \([0-9]*\).*/\1 \2/p"
}

# So ban dich theo tung may ben trong
ban_dich_theo_may() {
    r1 "show ip nat translations" | grep -E '^(udp|tcp|icmp) ' |
        awk '{split($3,a,":"); c[a[1]]++} END {for (k in c) printf "     %-15s %d bản dịch\n", k, c[k]}' || true
}

# curl_moi <container> -> in HTTP code cua MOT ket noi MOI (000 = khong mo duoc)
curl_moi() {
    docker exec "$1" curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://$IP_SERVER/" || true
}

# ping_nhan_vien -> in so goi nhan duoc tren 2
ping_nhan_vien() {
    docker exec "$NHAN_VIEN" ping -c 2 -W 1 "$IP_SERVER" 2>/dev/null |
        sed -n 's/.* \([0-9]*\) received.*/\1/p' || true
}

# ==============================================================================
# TAO TINH HUONG
# ==============================================================================

# may-loi mo SO_FLOW flow UDP, moi flow mot source port. Ban dich UDP song
# khoang 5 phut nen bang dung day suot buoi demo.
may_loi_tao_flow() {
    docker exec "$MAY_LOI" bash -c "
        for p in \$(seq 20001 $((20000 + SO_FLOW))); do
            (echo x | timeout 2 nc -u -p \$p -w1 $IP_SERVER 9 >/dev/null 2>&1 &)
        done
        sleep 3"
}

# Phien TCP mo TRUOC khi bang day: GET #1 ngay, GET #2 sau 25 giay
mo_phien_cu() {
    docker exec "$NHAN_VIEN" sh -c ': > /tmp/phien-cu.txt'
    docker exec -d "$NHAN_VIEN" sh -c "
        { printf 'GET / HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n'; sleep 25;
          printf 'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n'; sleep 2; } |
        timeout 35 nc $IP_SERVER 80 | grep -c '^HTTP/1.1 200' > /tmp/phien-cu.txt"
    sleep 1
}

# Doi phien cu ket thuc roi in so phan hoi 200 nhan duoc
doc_phien_cu() {
    local i kq
    for i in $(seq 1 40); do
        kq=$(docker exec "$NHAN_VIEN" cat /tmp/phien-cu.txt 2>/dev/null | tr -d ' \r')
        [ -n "$kq" ] && { echo "$kq"; return 0; }
        sleep 1
    done
    echo "?"
}
