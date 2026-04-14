#!/bin/bash

# 1. Tạo Bridge với tính năng vlan_filtering được kích hoạt
ip link add name br0 type bridge vlan_filtering 1
ip link set br0 up

# 2. Thêm các interface vật lý (hoặc ảo) vào bridge
# Giả sử eth1 là trunk port kết nối với Switch/Router
ip link set eth1 master br0
ip link set eth1 up

# 3. Cấu hình VLAN Filtering trên Trunk Port (eth1)
# Cho phép VLAN 10, 20, 30 đi qua
bridge vlan add dev eth1 vid 10
bridge vlan add dev eth1 vid 20
bridge vlan add dev eth1 vid 30

# 4. Cấu hình Access Ports (Giả sử eth2, eth3, eth4)
# eth2 thuộc VLAN 10
ip link set eth2 master br0
bridge vlan add dev eth2 vid 10 pvid untagged
bridge vlan del dev eth2 vid 1

# eth3 thuộc VLAN 20
ip link set eth3 master br0
bridge vlan add dev eth3 vid 20 pvid untagged
bridge vlan del dev eth3 vid 1

# eth4 thuộc VLAN 30
ip link set eth4 master br0
bridge vlan add dev eth4 vid 30 pvid untagged
bridge vlan del dev eth4 vid 1