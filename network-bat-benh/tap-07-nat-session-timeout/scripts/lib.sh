#!/usr/bin/env bash
# ==============================================================================
# Hang so & ham dung chung cho cac script cua tap 07
#
#   172.28.7.0/24 (LAN client) -- GATEWAY (NAT that, MASQUERADE) -- 172.28.17.0/24 (LAN server)
#
# TU TUONG CUA CA TAP:
#   NAT Gateway / Stateful Firewall khong "nho" mot ket noi TCP mai mai. No giu
#   MOT BANG (conntrack), moi dong la mot phien, va moi dong co DONG HO RIENG.
#   Khong co goi tin nao trong X giay -> dong bi XOA KHOI BANG, khong bao ai ca.
#   Goi tin ke tiep cua chinh phien do bi coi la XA LA (INVALID) roi bi DROP
#   IM LANG -- dung hanh vi "terminal dong cung roi Broken pipe" ngoai doi.
#
#   Bai hoc trung tam: TCP tu no KHONG co co che bao "phien sap het han". Ke
#   xoa entry la thiet bi TRUNG GIAN (gateway), khong phai client hay server --
#   ca hai dau vAn tin ket noi con song cho toi khi goi tin ke tiep di qua.
# ==============================================================================
GATEWAY=lab07-gateway
SERVER=lab07-server
CLIENT=lab07-client

IP_GW_LAN=172.28.7.254
IP_GW_WAN=172.28.17.254
IP_SERVER=172.28.17.10
IP_CLIENT=172.28.7.20

NET_LAN=172.28.7.0/24
NET_WAN=172.28.17.0/24

# ==============================================================================
# PHAN 1 — DUNG LAB / DAT LAI TRANG THAI
# ==============================================================================

buoc() { echo ""; echo "=========================================="; echo "🩺 $*"; echo "=========================================="; }

# ------------------------------------------------------------------------------
# Route tinh CHI SONG TRONG NETNS DANG CHAY — container restart la mat, phai
# dat lai moi lan 0-setup.sh (giong het tap 05).
# ------------------------------------------------------------------------------
dat_route() {
    docker exec $CLIENT ip route replace $NET_WAN via $IP_GW_LAN >/dev/null 2>&1
    docker exec $SERVER ip route replace $NET_LAN via $IP_GW_WAN >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# Dung lai luat FORWARD/NAT chuan tren gateway: stateful, chi cho NEW tu LAN
# client toi dung tcp/80 va udp/9 cua server, moi thu khac (dac biet INVALID)
# bi DROP IM LANG — dung hanh vi mot NAT Gateway/Firewall doanh nghiep that.
# ------------------------------------------------------------------------------
dung_luat_goc() {
    docker exec $GATEWAY sh -c '
        iptables -F FORWARD
        iptables -t nat -F POSTROUTING
        iptables -P FORWARD DROP
        iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A FORWARD -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
        iptables -A FORWARD -p udp --dport 9  -m conntrack --ctstate NEW -j ACCEPT
        iptables -A FORWARD -p icmp -j ACCEPT
        iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
        iptables -A FORWARD -j DROP
        iptables -t nat -A POSTROUTING -s '"$NET_LAN"' -d '"$NET_WAN"' -j MASQUERADE
    ' >/dev/null 2>&1
}

dat_tcp_timeout()   { docker exec $GATEWAY sysctl -qw net.netfilter.nf_conntrack_tcp_timeout_established="$1" >/dev/null 2>&1; }
dat_udp_timeout()   { docker exec $GATEWAY sysctl -qw net.netfilter.nf_conntrack_udp_timeout_stream="$1" >/dev/null 2>&1
                      docker exec $GATEWAY sysctl -qw net.netfilter.nf_conntrack_udp_timeout="$1"        >/dev/null 2>&1; }
dat_loose()         { docker exec $GATEWAY sysctl -qw net.netfilter.nf_conntrack_tcp_loose="$1"          >/dev/null 2>&1; }

doc_tcp_timeout()   { docker exec $GATEWAY sysctl -n net.netfilter.nf_conntrack_tcp_timeout_established 2>/dev/null | tr -d '\r'; }
doc_loose()         { docker exec $GATEWAY sysctl -n net.netfilter.nf_conntrack_tcp_loose 2>/dev/null | tr -d '\r'; }

# Doi nginx tren server: dai (keepalive_timeout 75s, mac dinh) | ngan (3s, MR3)
dat_nginx() {
    docker exec $SERVER sh -c "cp /etc/nginx/conf.d/${1}.conf.bak /etc/nginx/conf.d/default.conf && nginx -s reload" >/dev/null 2>&1
    sleep 0.3
}

# ------------------------------------------------------------------------------
# Xac nhan sysctl da AN THAT tren gateway — khong nuot loi (giong tap 06/07/08).
# ------------------------------------------------------------------------------
xac_nhan_sysctl() {
    local key="$1" want="$2" got
    got=$(docker exec $GATEWAY sysctl -n "$key" 2>/dev/null | tr -d '\r')
    if [ "$got" != "$want" ]; then
        echo "❌ LỖI: $key = ${got:-rỗng} (mong đợi $want). Kiểm tra 'privileged: true' trong docker-compose.yml." >&2
        exit 1
    fi
}

cho_server_san_sang() {
    local i
    for i in $(seq 1 25); do
        docker exec $CLIENT sh -c "timeout 1 nc -z $IP_SERVER 80" >/dev/null 2>&1 && return 0
        sleep 0.3
    done
    return 0
}

# ==============================================================================
# PHAN 2 — DO TU CLIENT (NAN NHAN)
# ==============================================================================

# ------------------------------------------------------------------------------
# Phep thu trung tam ca tap: MOT ket noi TCP duy nhat -> GET #1 -> idle N giay
# -> GET #2 tren CHINH ket noi do. In "so 200 nhan duoc/2".
# ------------------------------------------------------------------------------
hai_get_qua_idle() {
    local idle="${1:-7}"
    local w=$((idle + 6))
    docker exec $CLIENT sh -c "
      { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
        sleep $idle;
        printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
        sleep 3; } | nc -w $w $IP_SERVER 80 | grep -c '^HTTP/1.1 200'
    " 2>/dev/null | tr -d '\r '
}

# UDP: goi "goi1", idle N giay, goi "goi2" tren CUNG mot socket UDP — server
# la socat echo (cong 9). In tong so BYTE nhan lai: 8=ca hai goi duoc echo,
# 4=chi goi dau, 0=khong goi nao qua duoc.
hai_goi_udp_qua_idle() {
    local idle="${1:-7}"
    local w=$((idle + 5))
    docker exec $CLIENT sh -c "
      { printf 'goi1'; sleep $idle; printf 'goi2'; sleep 2; } | nc -u -w $w $IP_SERVER 9 | wc -c
    " 2>/dev/null | tr -d ' \r'
}

# So dong session cua port 80 con trong bang conntrack cua gateway
so_session_port80() {
    docker exec $GATEWAY sh -c "conntrack -L -p tcp --dport 80 2>/dev/null | wc -l" | tr -d ' \r'
}

xem_conntrack_80() {
    docker exec $GATEWAY sh -c "conntrack -L -p tcp --dport 80 2>/dev/null || echo '(bảng rỗng)'"
}
