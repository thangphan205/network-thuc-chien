#!/bin/bash

# Kịch bản: Mô phỏng Container truy cập Internet qua Bridge và NAT
# Các bước thực hiện:
# 1. Tạo Bridge (đóng vai trò Switch ảo)
# 2. Tạo Namespace (đóng vai trò Container)
# 3. Nối Container vào Bridge bằng cặp veth
# 4. Cấu hình IP và Default Gateway cho Container
# 5. Cấu hình NAT (IP Masquerade) trên Host để cho phép ra Internet

echo "--- 1. Xóa cấu hình cũ (nếu có) ---"
ip netns del ns-container 2>/dev/null
ip link del br-int 2>/dev/null
iptables -t nat -F

echo "--- 2. Tạo Bridge và cấu hình IP cho Host tại Bridge ---"
ip link add br-int type bridge
ip addr add 172.18.0.1/24 dev br-int
ip link set br-int up

echo "--- 3. Tạo Container (Namespace) và kết nối vào Bridge ---"
ip netns add ns-container

# Tạo cặp veth: veth-con (trong container) và veth-host (cắm vào bridge)
ip link add veth-con type veth peer name veth-host

# Cắm veth-host vào bridge
ip link set veth-host master br-int
ip link set veth-host up

# Đưa veth-con vào trong namespace
ip link set veth-con netns ns-container

echo "--- 4. Cấu hình IP và Routing bên trong Container ---"
ip netns exec ns-container ip addr add 172.18.0.10/24 dev veth-con
ip netns exec ns-container ip link set veth-con up
ip netns exec ns-container ip link set lo up

# Thiết lập Default Gateway trỏ về IP của Bridge trên Host
ip netns exec ns-container ip route add default via 172.18.0.1

echo "--- 5. Cấu hình NAT và Forwarding trên Host ---"
# Cho phép Linux chuyển tiếp gói tin (IP Forwarding)
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Cấu hình IPTables để NAT các gói tin đi ra từ dải mạng của bridge
# Thay đổi 'eth0' bằng interface mạng chính của máy bạn nếu cần (ví dụ: ens33, wlan0)
MAIN_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
iptables -t nat -A POSTROUTING -s 172.18.0.0/24 -o $MAIN_IF -j MASQUERADE

echo "--- 6. KIỂM TRA KẾT NỐI ---"
echo "Kiểm tra ping tới Bridge (Gateway):"
ip netns exec ns-container ping 172.18.0.1 -c 2

echo -e "\nKiểm tra ping ra Internet (8.8.8.8):"
if ip netns exec ns-container ping 8.8.8.8 -c 3; then
    echo -e "\n=> THÀNH CÔNG: Container đã có thể truy cập Internet!"
else
    echo -e "\n=> THẤT BẠI: Kiểm tra lại cấu hình Firewall hoặc DNS."
fi

echo -e "\n--- GIẢI THÍCH CƠ CHẾ ---"
echo "1. Gói tin từ Container (172.18.0.10) gửi đến 8.8.8.8."
echo "2. Nó nhìn vào bảng routing và gửi đến Default Gateway (172.18.0.1 - Bridge)."
echo "3. Host nhận được gói tin, nhờ IP Forwarding, nó chuyển gói tin ra interface vật lý ($MAIN_IF)."
echo "4. Nhờ quy tắc IPTables MASQUERADE, địa chỉ nguồn 172.18.0.10 được thay bằng IP thật của Host."
echo "5. Khi gói tin phản hồi quay lại, Host thực hiện ngược lại (DNAT) để đưa về cho Container."
