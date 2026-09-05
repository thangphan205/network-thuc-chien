#!/usr/bin/env bash
# ==============================================================================
# Hằng số & hàm dùng chung cho các script của tập 5
#
#   CLIENT LAN 172.28.51.0/24 --+
#   LB / DMZ   172.28.52.0/24 --+-- [ router 3 chân ]
#   APP TIER   172.28.53.0/24 --+
# ==============================================================================
VIP=172.28.52.100

CLIENT_REMOTE=lab05-client-remote
CLIENT_LAN=lab05-client-lan
NODE_A=lab05-node-a
NODE_B=lab05-node-b
WEB_1=lab05-web-1
WEB_2=lab05-web-2
ROUTER=lab05-router

CLIENT_NET=172.28.51.0/24 ; R_CLIENT=172.28.51.254 ; IP_CLIENT_REMOTE=172.28.51.20
LB_NET=172.28.52.0/24     ; R_LB=172.28.52.254     ; IP_CLIENT_LAN=172.28.52.20
APP_NET=172.28.53.0/24    ; R_APP=172.28.53.254

# ------------------------------------------------------------------------------
# Tra tên interface trên ROUTER theo tiền tố IP.
#
# Vì sao KHÔNG hardcode eth0/eth1/eth2? Docker KHÔNG đảm bảo thứ tự interface
# trên container nhiều chân — thứ tự phụ thuộc vào lúc attach network, đổi giữa
# các lần `up`. Hardcode là kiểu bug chỉ hiện ra trên máy người khác.
# ------------------------------------------------------------------------------
r_if() {
    docker exec "$ROUTER" ip -o -4 addr show 2>/dev/null \
        | awk -v p="$1" '$4 ~ "^"p {print $2; exit}' | tr -d '\r'
}
r_cli_if() { r_if '172\\.28\\.51\\.'; }
r_lb_if()  { r_if '172\\.28\\.52\\.'; }
r_app_if() { r_if '172\\.28\\.53\\.'; }

# Ai đang giữ VIP?
vip_owner() {
    if docker exec $NODE_A ip -o addr show 2>/dev/null | grep -q "$VIP"; then
        echo "node-a"
    elif docker exec $NODE_B ip -o addr show 2>/dev/null | grep -q "$VIP"; then
        echo "node-b"
    else
        echo "(khong ai)"
    fi
}

mac_of() { docker exec "$1" cat /sys/class/net/eth0/address 2>/dev/null; }

# ------------------------------------------------------------------------------
# Nhớ MAC của 2 node ra file.
#
# Vì sao cần? Ca bệnh của tập này là "MAC của một máy ĐÃ CHẾT còn nằm trong bảng
# ARP". Máy chết rồi thì `docker exec` không đọc được MAC của nó nữa — mà đó lại
# đúng là cái MAC ta cần gọi tên. Không cache thì mọi bản in đều ra "(lạ)".
# ------------------------------------------------------------------------------
MAC_CACHE=/tmp/lab05-mac-cache
luu_mac() {
    { echo "node-a $(mac_of $NODE_A)"
      echo "node-b $(mac_of $NODE_B)"; } | awk 'NF==2' > "$MAC_CACHE" 2>/dev/null || true
}

# MAC mà ROUTER đang ôm cho VIP — đây mới là ổ bệnh thật khi có định tuyến.
router_vip_mac() {
    docker exec $ROUTER ip neigh show "$VIP" dev "$(r_lb_if)" 2>/dev/null \
        | awk '{print $3}'
}

# MAC mà client CÙNG LAN đang ôm cho VIP.
client_lan_vip_mac() {
    docker exec $CLIENT_LAN ip neigh show "$VIP" 2>/dev/null | awk '{print $5}'
}

# Dịch MAC sang tên node cho dễ đọc.
mac_to_node() {
    local m="$1" ten
    [ -z "$m" ] && { echo "(chua hoc)"; return; }
    if   [ "$m" = "$(mac_of $NODE_A)" ]; then echo "node-a" ; return
    elif [ "$m" = "$(mac_of $NODE_B)" ]; then echo "node-b" ; return
    fi
    # Không khớp máy nào đang sống -> tra cache. Khớp cache nghĩa là MAC này
    # thuộc về một node ĐÃ CHẾT: đúng chữ ký của ca bệnh.
    ten=$(awk -v m="$m" '$2==m {print $1}' "$MAC_CACHE" 2>/dev/null | head -1)
    if [ -n "$ten" ]; then echo "$ten ĐÃ CHẾT"; else echo "(la)"; fi
}

# ------------------------------------------------------------------------------
# Giả lập ARP timeout kiểu Cisco IOS (14400 giây = 4 tiếng) trên chân .52.
#
# ⚠️ base_reachable_time_ms CHỈ tác động lên entry HỌC MỚI. Set xong bắt buộc
#    phải `ip neigh flush` rồi gọi VIP một lần cho router học lại, nếu không
#    entry cũ vẫn giữ hành vi NUD mặc định và kịch bản Cisco không tái hiện được.
#
# Docker mount /proc/sys READ-ONLY nên phải remount rw trước — router được cấp
# SYS_ADMIN riêng cho việc này.
# ------------------------------------------------------------------------------
mo_proc_sys() {
    docker exec $ROUTER mount -o remount,rw /proc/sys 2>/dev/null || true
}

set_arp_cisco() {
    local IF; IF=$(r_lb_if) ; mo_proc_sys
    docker exec $ROUTER sysctl -qw "net.ipv4.neigh.$IF.base_reachable_time_ms=14400000"
    docker exec $ROUTER sysctl -qw "net.ipv4.neigh.$IF.gc_stale_time=14400"
    docker exec $ROUTER sysctl -qw "net.ipv4.neigh.$IF.delay_first_probe_time=14400"
}

# Trả router về hành vi Linux mặc định (có NUD -> tự dò lại sau ~30 giây).
set_arp_linux() {
    local IF; IF=$(r_lb_if) ; mo_proc_sys
    docker exec $ROUTER sysctl -qw "net.ipv4.neigh.$IF.base_reachable_time_ms=30000"
    docker exec $ROUTER sysctl -qw "net.ipv4.neigh.$IF.gc_stale_time=60"
    docker exec $ROUTER sysctl -qw "net.ipv4.neigh.$IF.delay_first_probe_time=5"
}

# Chờ tới khi client-remote gọi được VIP (tối đa $1 giây)
wait_vip_up() {
    for _ in $(seq "${1:-30}"); do
        docker exec $CLIENT_REMOTE curl -sf --max-time 2 -o /dev/null "http://$VIP/" && return 0
        sleep 1
    done
    return 1
}

# Chờ tới khi node chỉ định thực sự cầm VIP (tối đa $2 giây).
# Cần thiết vì lúc khởi động, cả 2 keepalived lên gần như cùng lúc: node-b có
# thể lên MASTER trước vài trăm ms rồi mới bị node-a (priority cao hơn) giành
# lại. Không chờ thì demo bắt đầu từ trạng thái gây hiểu nhầm.
wait_vip_owner() {
    for _ in $(seq "${2:-30}"); do
        [ "$(vip_owner)" = "$1" ] && return 0
        sleep 1
    done
    return 1
}

# ------------------------------------------------------------------------------
# Cài lại route tĩnh cho một container.
#
# ⚠️ BẮT BUỘC gọi sau MỌI lần `docker compose start/restart`. Route thêm bằng
#    `ip route` chỉ sống trong netns đang chạy — container khởi động lại là mất
#    sạch. Trong topology 3 tầng, node mất route về .53 nghĩa là HAProxy của nó
#    không với tới backend -> nó lên MASTER và trả 503, làm hỏng kịch bản mà
#    KHÔNG có thông báo lỗi nào.
# ------------------------------------------------------------------------------
cai_route() {
    case "$1" in
        $NODE_A|$NODE_B)
            docker exec "$1" ip route replace $CLIENT_NET via $R_LB 2>/dev/null || true
            docker exec "$1" ip route replace $APP_NET    via $R_LB 2>/dev/null || true ;;
        $CLIENT_REMOTE)
            docker exec "$1" ip route replace $LB_NET     via $R_CLIENT 2>/dev/null || true ;;
        $WEB_1|$WEB_2)
            docker exec "$1" ip route replace $LB_NET     via $R_APP 2>/dev/null || true ;;
    esac
}

# ------------------------------------------------------------------------------
# Hồi phục cụm HA về trạng thái chuẩn mà KHÔNG build lại image.
# Dùng cho các kịch bản cần gây bệnh nhiều lần trong một lần chạy.
# ------------------------------------------------------------------------------
hoi_phuc_ha() {
    docker compose start node-a >/dev/null 2>&1 || true
    sleep 2
    for N in $NODE_A $NODE_B; do
        docker exec "$N" pkill -9 keepalived 2>/dev/null || true
        docker exec "$N" ip addr del $VIP/24 dev eth0 2>/dev/null || true
        cai_route "$N"
        docker exec "$N" sh -c 'pgrep haproxy >/dev/null || haproxy -f /etc/haproxy/haproxy.cfg -D' 2>/dev/null || true
    done
    docker exec $NODE_A ka-start /etc/keepalived/keepalived.conf 2>/dev/null || true
    sleep 2
    docker exec $NODE_B ka-start /etc/keepalived/keepalived.conf 2>/dev/null || true
    wait_vip_up 45 >/dev/null 2>&1
    wait_vip_owner node-a 30 >/dev/null 2>&1
    luu_mac
}

# Gây ca bệnh: node-b cướp VIP bằng script tự chế, KHÔNG phát GARP.
gay_benh_stale_arp() {
    docker exec $NODE_B ka-stop >/dev/null 2>&1
    docker compose kill node-a >/dev/null 2>&1
    sleep 3
    docker exec $NODE_B ip addr replace $VIP/24 dev eth0
    sleep 2
}

# In song song 2 bảng ARP quan trọng nhất của lab.
in_bang_arp() {
    local RMAC CMAC
    RMAC=$(router_vip_mac) ; CMAC=$(client_lan_vip_mac)
    printf "   %-14s %-20s -> %s\n" "router(.52):" "${RMAC:-(chua hoc)}" "$(mac_to_node "$RMAC")"
    printf "   %-14s %-20s -> %s\n" "client-lan:"  "${CMAC:-(chua hoc)}" "$(mac_to_node "$CMAC")"
}
