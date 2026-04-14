# 1. Tạo namespace cho "Container A" và "Container B"
ip netns add ns-a
ip netns add ns-b

# 2. Tạo cặp veth (veth-a nối với veth-b)
ip link add veth-a type veth peer name veth-b

# 3. Chuyển các đầu cáp vào đúng namespace
ip link set veth-a netns ns-a
ip link set veth-b netns ns-b

# 4. Cấu hình IP cho từng đầu
ip netns exec ns-a ip addr add 10.0.0.1/24 dev veth-a
ip netns exec ns-b ip addr add 10.0.0.2/24 dev veth-b

# 5. Kích hoạt interface (mặc định chúng ở trạng thái DOWN)
ip netns exec ns-a ip link set veth-a up
ip netns exec ns-a ip link set lo up
ip netns exec ns-b ip link set veth-b up
ip netns exec ns-b ip link set lo up

# 6. Kiểm tra kết nối
ip netns exec ns-a ping 10.0.0.2 -c 3