#!/bin/bash
# ==============================================================================
# Khởi động node Load Balancer: sinh keepalived.conf từ biến môi trường,
# chạy HAProxy + Keepalived ở nền, rồi giữ container sống.
#
# Vì sao KHÔNG chạy keepalived ở foreground làm PID 1?
#   Bài lab cần tắt/bật riêng Keepalived (mô phỏng "script HA tự chế") mà
#   container vẫn phải sống để HAProxy tiếp tục phục vụ. Nếu keepalived là PID 1
#   thì `pkill keepalived` sẽ giết luôn cả container.
#   (docker-compose đặt `init: true` để tini làm PID 1 và THU DỌN tiến trình
#    keepalived đã chết — nếu không sẽ còn lại zombie <defunct>.)
# ==============================================================================
set -e

VIP="${VIP:-172.28.52.100}"
IFACE="${IFACE:-eth0}"

# ------------------------------------------------------------------------------
# $1 = file đích, $2 = state, $3 = các dòng phụ chèn vào vrrp_instance
#                                 (nopreempt / use_vmac — rỗng nếu không dùng)
# ------------------------------------------------------------------------------
gen_conf() {
cat > "$1" <<KEOF
global_defs {
    router_id ${ROUTER_ID}
    enable_script_security
    script_user root
}

# Theo dõi HAProxy: HAProxy chết thì hạ priority để node kia cướp VIP.
vrrp_script chk_haproxy {
    script "/usr/local/bin/check_haproxy.sh"
    interval 2
    timeout 2
    weight -30
    fall 2
    rise 2
}

vrrp_instance VI_LB {
    state $2
    interface ${IFACE}
    virtual_router_id 51
    priority ${VRRP_PRIORITY}
    advert_int 1
$3
    # VRRPv2 simple auth: TỐI ĐA 8 ký tự, dài hơn sẽ bị cắt cụt kèm cảnh báo
    # "Truncating auth_pass to 8 characters".
    authentication {
        auth_type PASS
        auth_pass 9pingHA1
    }

    # Các keyword garp_* thuộc vrrp_instance, KHÔNG phải global_defs.
    # Đặt nhầm chỗ keepalived sẽ báo "Unknown keyword 'garp_master_delay'".
    garp_master_delay 1
    garp_master_repeat 3
    garp_master_refresh 60
    garp_master_refresh_repeat 2

    virtual_ipaddress {
        ${VIP}/24 dev ${IFACE}
    }

    track_script {
        chk_haproxy
    }
}
KEOF
}

# Cấu hình mặc định: có preempt (node priority cao luôn giành lại VIP)
gen_conf /etc/keepalived/keepalived.conf "${VRRP_STATE}" ""

# Cấu hình đối chứng cho cảnh "preempt": nopreempt CHỈ hợp lệ khi state = BACKUP.
# Đặt state MASTER kèm nopreempt thì keepalived báo lỗi và bỏ qua nopreempt.
gen_conf /etc/keepalived/keepalived-nopreempt.conf "BACKUP" "    nopreempt"

# Cấu hình đối chứng cho cảnh "use_vmac" (RFC 5798 — MAC ảo đi theo VIP).
#   use_vmac      -> keepalived tạo interface macvlan `vrrp51`, VIP nằm trên đó.
#                    MAC của VIP là 00:00:5e:00:01:<VRID> ở CẢ HAI node, nên khi
#                    failover thì bảng ARP của router KHÔNG cần cập nhật gì cả
#                    -> ca bệnh của tập này biến mất tận gốc.
#   vmac_xmit_base-> phát VRRP advertisement ra interface THẬT thay vì ra macvlan.
#                    Thiếu dòng này nhiều switch/bridge sẽ nuốt advertisement.
gen_conf /etc/keepalived/keepalived-vmac.conf "${VRRP_STATE}" \
"    use_vmac vrrp51
    vmac_xmit_base"

echo "[entrypoint] $(hostname): khởi động HAProxy..."
haproxy -f /etc/haproxy/haproxy.cfg -D

# Cảnh 7 cần cấu hình nopreempt SỐNG SÓT qua lần restart container:
# `docker compose start` chạy lại entrypoint này, nếu luôn nạp bản mặc định thì
# node vừa hồi phục sẽ quay về chế độ preempt và giành lại VIP -> hỏng kịch bản.
KA_CONF=/etc/keepalived/keepalived.conf
if [ -f /etc/keepalived/USE_NOPREEMPT ]; then
    KA_CONF=/etc/keepalived/keepalived-nopreempt.conf
    echo "[entrypoint] $(hostname): phát hiện cờ USE_NOPREEMPT -> dùng cấu hình nopreempt"
elif [ -f /etc/keepalived/USE_VMAC ]; then
    KA_CONF=/etc/keepalived/keepalived-vmac.conf
    echo "[entrypoint] $(hostname): phát hiện cờ USE_VMAC -> dùng cấu hình use_vmac"
fi

echo "[entrypoint] $(hostname): khởi động Keepalived (priority ${VRRP_PRIORITY}, conf=$(basename $KA_CONF))..."
keepalived -D -f "$KA_CONF"

echo "[entrypoint] $(hostname): sẵn sàng."
exec sleep infinity
