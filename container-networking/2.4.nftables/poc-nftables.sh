#!/bin/bash

# Kịch bản: Mô phỏng Container truy cập Internet qua Bridge và NAT sử dụng NFTABLES
# 1. Tạo Bridge (Switch ảo)
# 2. Tạo Namespace (Container)
# 3. Nối Container vào Bridge
# 4. Cấu hình IP và Routing
# 5. Cấu hình NAT Masquerade bằng nftables

echo "--- 1. Xóa cấu hình cũ (nếu có) ---"
ip netns del ns-container 2>/dev/null
ip link del br-int 2>/dev/null
# Xóa toàn bộ ruleset nftables để tránh xung đột
nft flush ruleset

echo "--- 2. Tạo Bridge và cấu hình IP cho Host ---"
ip link add br-int type bridge
ip addr add 172.19.0.1/24 dev br-int
ip link set br-int up

echo "--- 3. Tạo Container (Namespace) và kết nối vào Bridge ---"
ip netns add ns-container
ip link add veth-con type veth peer name veth-host
ip link set veth-host master br-int
ip link set veth-host up
ip link set veth-con netns ns-container

echo "--- 4. Cấu hình IP và Routing bên trong Container ---"
ip netns exec ns-container ip addr add 172.19.0.10/24 dev veth-con
ip netns exec ns-container ip link set veth-con up
ip netns exec ns-container ip link set lo up
ip netns exec ns-container ip route add default via 172.19.0.1

echo "--- 5. Cấu hình NAT (Masquerade) bằng nftables ---"
# Kích hoạt IP Forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Lấy interface mạng chính
MAIN_IF=$(ip route | grep default | awk '{print $5}' | head -n1)

# Tạo table 'nat_poc' (family ip)
nft add table ip nat_poc

# Tạo chain 'postrouting' với hook postrouting
nft add chain ip nat_poc postrouting { type nat hook postrouting priority srcnat \; }

# Thêm rule Masquerade cho traffic đi ra từ dải mạng của bridge
nft add rule ip nat_poc postrouting ip saddr 172.19.0.0/24 oifname "$MAIN_IF" masquerade

echo "--- 6. KIỂM TRA KẾT NỐI ---"
echo "Kiểm tra ping tới Gateway (Bridge):"
ip netns exec ns-container ping 172.19.0.1 -c 2

echo -e "\nKiểm tra ping ra Internet (8.8.8.8):"
if ip netns exec ns-container ping 8.8.8.8 -c 3; then
    echo -e "\n=> THÀNH CÔNG: Container đã có thể truy cập Internet qua nftables!"
else
    echo -e "\n=> THẤT BẠI: Kiểm tra lại cấu hình nftables hoặc interface $MAIN_IF."
fi

echo -e "\n--- HIỂN THỊ CẤU HÌNH NFTABLES ---"
nft list ruleset

echo -e "\n--- GIẢI THÍCH CƠ CHẾ NFTABLES ---"
echo "1. 'table ip nat_poc': Tạo một không gian chứa các rules liên quan đến NAT."
echo "2. 'chain postrouting': Đăng ký vào hook 'postrouting' của kernel, nơi NAT xảy ra sau khi định tuyến."
echo "3. 'masquerade': Tự động thay đổi IP nguồn của gói tin từ 172.19.0.10 thành IP của $MAIN_IF."
echo "4. Ưu điểm: nftables cho phép gom nhóm rules và quản lý tập trung thay vì các bảng rời rạc của iptables."

echo -e "\nĐể dọn dẹp sau khi thử nghiệm, hãy chạy lệnh:"
echo "ip netns del ns-container && ip link del br-int && nft flush ruleset"
