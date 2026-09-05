#!/usr/bin/env bash
# ==============================================================================
# HÀM DÙNG CHUNG CHO CÁC SCRIPT CỦA LAB
# ==============================================================================
BRIDGE="br-server"
VIP="172.28.52.100"
CLIENT_IP="172.28.51.20"

# Tìm container theo tên node, khớp CHÍNH XÁC tiền tố lab của tập 5.
# Không dùng `docker ps --filter name=client` vì filter của docker khớp theo
# chuỗi con: trên host có sẵn lab khác với container tên "client-a"/"client-b"
# thì script sẽ thao tác nhầm container.
clab_ctr() {
    docker ps --format '{{.Names}}' \
        | grep -E "^clab-tap05_garp_ha(_linux)?-$1\$" \
        | head -1
}

# Tạo Linux bridge cho Server LAN. Containerlab KHÔNG tự tạo bridge cho
# `kind: bridge`, nó chỉ gắn veth vào bridge có sẵn.
ensure_bridge() {
    if ! ip link show "$BRIDGE" >/dev/null 2>&1; then
        echo "🔧 Tạo Linux bridge '$BRIDGE' cho Server LAN..."
        sudo ip link add name "$BRIDGE" type bridge
    fi
    sudo ip link set "$BRIDGE" up
    # VRRP chạy trên multicast 224.0.0.18. Bridge bật IGMP snooping mà không có
    # querier có thể lọc mất advertisement -> hai server không thấy nhau.
    echo 0 | sudo tee "/sys/class/net/$BRIDGE/bridge/multicast_snooping" >/dev/null 2>&1 || true
}
