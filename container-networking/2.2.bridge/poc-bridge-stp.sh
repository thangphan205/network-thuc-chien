#!/bin/bash

# Kịch bản: Giả lập 3 Switch (br0, br1, br2) nối vòng tròn.
# Mục tiêu: Quan sát STP tự động chặn 1 cổng để tránh Loop.

echo "--- 1. Xóa cấu hình cũ (nếu có) ---"
ip link del br0 2>/dev/null
ip link del br1 2>/dev/null
ip link del br2 2>/dev/null

echo "--- 2. Tạo 3 Bridge (Switch) ---"
ip link add br0 type bridge
ip link add br1 type bridge
ip link add br2 type bridge

ip link set br0 up
ip link set br1 up
ip link set br2 up

echo "--- 3. Tạo các cặp veth để nối các Bridge ---"
# Nối br0 <-> br1
ip link add veth01-a type veth peer name veth01-b
# Nối br1 <-> br2
ip link add veth12-a type veth peer name veth12-b
# Nối br2 <-> br0 (Tạo thành vòng khép kín - LOOP)
ip link add veth20-a type veth peer name veth20-b

echo "--- 4. Cắm dây vào các Bridge ---"
# br0 nối với br1 và br2
ip link set veth01-a master br0
ip link set veth20-b master br0

# br1 nối với br0 và br2
ip link set veth01-b master br1
ip link set veth12-a master br1

# br2 nối với br1 và br0
ip link set veth12-b master br2
ip link set veth20-a master br2

# Bật tất cả các interface
ip link set veth01-a up
ip link set veth01-b up
ip link set veth12-a up
ip link set veth12-b up
ip link set veth20-a up
ip link set veth20-b up

echo "--- 5. Kích hoạt STP trên các Bridge ---"
# Nếu không có STP, mạng sẽ bị treo ngay lập tức do Broadcast Storm
ip link set br0 type bridge stp_state 1
ip link set br1 type bridge stp_state 1
ip link set br2 type bridge stp_state 1

# Theo tiêu chuẩn 802.1D, Forward Delay mặc định là 15s cho mỗi trạng thái (Listening và Learning).
# Tổng thời gian hội tụ lý thuyết là 30s. Trên Linux, giá trị này có thể thấp hơn tùy cấu hình,
# nhưng 30s là con số an toàn nhất để đảm bảo tất cả các port đã ổn định trạng thái Forwarding/Blocking.
echo "Đang chờ 30 giây để STP hội tụ (Listening 15s + Learning 15s)..."
sleep 30

echo "--- 6. KIỂM TRA TRẠNG THÁI ---"

echo "Trạng thái br0:"
brctl showstp br0 | grep -E "state|port id"

echo -e "\nTrạng thái br1:"
brctl showstp br1 | grep -E "state|port id"

echo -e "\nTrạng thái br2:"
brctl showstp br2 | grep -E "state|port id"

echo -e "\n--- GIẢI THÍCH CHO SINH VIÊN ---"
echo "1. Mô hình: br0 -- br1 -- br2 -- br0 (Vòng tròn)."
echo "2. Nếu không có STP: Một gói tin Broadcast sẽ chạy vô tận quanh 3 bridge, làm CPU 100%."
echo "3. Kết quả STP: Trong 6 cổng (mỗi bridge 2 cổng), bạn sẽ thấy 1 cổng có trạng thái 'blocking'."
echo "4. Cổng 'blocking' này ngắt vòng lặp, biến sơ đồ vòng tròn thành sơ đồ đường thẳng (Tree)."
echo "5. Thử nghiệm: Nếu bạn 'ip link set <cổng_đang_chạy> down', STP sẽ tự mở cổng 'blocking' để cứu mạng."

echo -e "\n--- 7. THỬ NGHIỆM TẮT STP ĐỂ GÂY LOOP (CẢNH BÁO: TĂNG CPU) ---"
read -p "Nhấn Enter để tắt STP và quan sát hiện tượng Loop..."

ip link set br0 type bridge stp_state 0
ip link set br1 type bridge stp_state 0
ip link set br2 type bridge stp_state 0

echo "Đã tắt STP. Đang gửi 1 gói tin broadcast để kích hoạt Broadcast Storm..."
# Tạo một namespace tạm thời để gửi gói tin broadcast
ip netns add ns-temp
ip link add veth-temp type veth peer name veth-br0
ip link set veth-temp netns ns-temp
ip link set veth-br0 master br0
ip link set veth-br0 up
ip netns exec ns-temp ip link set veth-temp up
ip netns exec ns-temp ip addr add 10.0.0.100/24 dev veth-temp
ip netns exec ns-temp ping -b 10.0.0.255 -c 1 -W 1 > /dev/null 2>&1 &

echo "Hãy kiểm tra lệnh 'top' hoặc 'htop' để thấy CPU của tiến trình ksoftirqd tăng cao."
echo "Sử dụng 'tcpdump -i veth01-a' để thấy hàng ngàn gói tin lặp lại."
