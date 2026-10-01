#!/usr/bin/env bash
# ==============================================================================
# Hang so & ham dung chung cho cac script cua tap 08
#
#   client 172.28.8.20 --(fw-a .251 | fw-b .252)-- server 172.28.18.10
#
# TU TUONG CUA CA TAP:
#   Asymmetric routing KHONG phai la loi. Goi di theo mot duong, goi ve theo duong
#   khac -- mang van chay. Ca benh chi xay ra khi CO THIET BI STATEFUL o giua:
#   moi firewall giu bang conntrack RIENG, va chi tha goi cua ket noi ma no DA THAY
#   tu dau. Duong ve di qua firewall CHUA TUNG THAY SYN -> goi bi coi INVALID -> DROP.
#
#   Ping van thong vi ICMP echo khong can trang thai ket noi de duoc phep.
# ==============================================================================
CLIENT=lab08-client
SERVER=lab08-server
FWA=lab08-fw-a
FWB=lab08-fw-b

IP_CLIENT=172.28.8.20
IP_SERVER=172.28.18.10
IP_FWA_C=172.28.8.251; IP_FWA_S=172.28.18.251
IP_FWB_C=172.28.8.252; IP_FWB_S=172.28.18.252
NET_C=172.28.8.0/24
NET_S=172.28.18.0/24

buoc() { echo ""; echo "=========================================="; echo "🩺 $*"; echo "=========================================="; }

# route tinh chi song trong netns dang chay -> dat lai moi lan 0-setup.sh
dat_route_client() { docker exec $CLIENT ip route replace $NET_S via $IP_FWA_C >/dev/null 2>&1; }

# server_ve a|b : server tra loi ve LAN client bang fw-a (doi xung) hay fw-b (bat doi xung)
server_ve() {
    local via=$IP_FWA_S
    [ "$1" = "b" ] && via=$IP_FWB_S
    docker exec $SERVER ip route replace $NET_C via $via >/dev/null 2>&1
}
server_dang_ve() {
    docker exec $SERVER ip route get $IP_CLIENT 2>/dev/null | sed -n 's/.* via \([0-9.]*\).*/\1/p' | head -1
}

# stateful | permissive  (fw = $FWA | $FWB)
luat_stateful() {
    docker exec $1 sh -c "
      iptables -F FORWARD; iptables -t nat -F POSTROUTING
      iptables -P FORWARD DROP
      iptables -A FORWARD -p icmp -j ACCEPT
      iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
      iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A FORWARD -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
      iptables -A FORWARD -j DROP" >/dev/null 2>&1
}
luat_permissive() {
    docker exec $1 sh -c "iptables -F FORWARD; iptables -t nat -F POSTROUTING; iptables -P FORWARD ACCEPT" >/dev/null 2>&1
}
dat_loose() { docker exec $1 sysctl -qw net.netfilter.nf_conntrack_tcp_loose="$2" >/dev/null 2>&1; }
xoa_conntrack() { docker exec $1 conntrack -F >/dev/null 2>&1 || true; }
# Ca truoc (vd KB2) de lai socket SYN_RECV tren server; no tiep tuc gui lai SYN-ACK
# toi ~31s va bi fw-b dem la goi INVALID, lam sai so lieu cua ca ke tiep. Doi no tat
# (chi 1 lan moi tien trinh) truoc khi zero bo dem.
cho_het_synack_cu() {
    [ -n "${_DA_CHO_SYNACK:-}" ] && return 0
    _DA_CHO_SYNACK=1
    local i n
    for i in $(seq 1 40); do
        n=$(docker exec $SERVER sh -c "ss -tn state syn-recv 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null | tr -d ' \r')
        [ "${n:-0}" = "0" ] && return 0
        [ "$i" = "1" ] && echo "  ⏳ Chờ SYN-ACK gửi lại của ca trước tắt hẳn (tối đa 40s)..."
        sleep 1
    done
    return 0
}
zero_dem() { cho_het_synack_cu; docker exec $1 iptables -Z FORWARD >/dev/null 2>&1 || true; }

# so goi INVALID da bi DROP tren mot firewall
so_invalid() {
    docker exec $1 iptables -L FORWARD -v -n -x 2>/dev/null | awk '/INVALID/ {print $1; exit}'
}
so_conntrack_80() {
    docker exec $1 sh -c "conntrack -L -p tcp --dport 80 2>/dev/null | wc -l" | tr -d ' \r'
}

# curl mot ket noi MOI: in ma http (000 = khong bat tay xong)
curl_thu() {
    docker exec $CLIENT curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 http://$IP_SERVER/ 2>/dev/null || true
}
ping_thu() {
    docker exec $CLIENT ping -c 2 -W 1 $IP_SERVER >/dev/null 2>&1 && echo THONG || echo DUT
}
# curl exit code (0=ok, 28=timeout, 7=refused)
curl_exit() {
    docker exec $CLIENT curl -s -o /dev/null --connect-timeout 3 --max-time 5 http://$IP_SERVER/ >/dev/null 2>&1
    echo $?
}

# Mot ket noi TCP: GET#1 -> doi $1 giay -> GET#2 tren CHINH ket noi do. In so HTTP 200.
# Giua hai GET, script goi co the chay mot lenh (vd doi route) bang bien MID_CMD.
hai_get_giua_chung() {
    local wait="${1:-4}"
    docker exec $CLIENT sh -c "
      { printf 'GET / HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n';
        sleep $wait;
        printf 'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n';
        sleep 2; } | nc -w $((wait + 6)) $IP_SERVER 80 | grep -c '^HTTP/1.1 200'
    " 2>/dev/null | tr -d ' \r'
}

cho_san_sang() {
    local i
    for i in $(seq 1 25); do
        docker exec $SERVER sh -c "wget -q -O /dev/null http://127.0.0.1/" >/dev/null 2>&1 && return 0
        sleep 0.3
    done
    return 0
}
