# Tái hiện lại bài lab routing + NAT vừa rồi — nhưng dùng nftables hoàn toàn. Flush iptables trước để tránh conflict.
# 0. Flush iptables cũ (nếu đang test)
$ sudo iptables -t nat -F $ sudo iptables -F
# 1. Tạo table (family inet = IPv4 + IPv6)
$ sudo nft add table inet container_nat
# 2. Tạo chain postrouting (SNAT ra ngoài)
$ sudo nft add chain inet container_nat postroute '{ type nat hook postrouting priority 100; }'
# 3. Tạo chain prerouting (DNAT vào trong)
$ sudo nft add chain inet container_nat preroute '{ type nat hook prerouting priority -100; }'
# 4. Rule MASQUERADE (SNAT)
$ sudo nft add rule inet container_nat postroute ip saddr 10.0.0.0/24 oifname != "br0" masquerade
# 5. Rule DNAT (port forwarding)
$ sudo nft add rule inet container_nat preroute tcp dport 8080 dnat to 10.0.0.1:80

# Xem toàn bộ ruleset — một lệnh duy nhất
$ sudo nft list ruleset

# Lưu ruleset ra file (để load lại sau reboot)
$ sudo nft list ruleset > /etc/nftables.conf

# Load atomic từ file (all-or-nothing)
$ sudo nft -f /etc/nftables.conf # nếu file có lỗi → không apply gì cả # iptables không có tính năng này

# Flush toàn bộ để dọn dẹp
$ sudo nft flush ruleset