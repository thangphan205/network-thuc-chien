#!/bin/bash
# ==============================================================================
# Lab 1.1: Inspect Network Namespace của Pod từ Worker Node
# Kịch bản thực hành từng bước. 
# Lưu ý: Các lệnh có chữ [Control Plane] chạy trên máy quản lý K8s, 
# các lệnh [Worker Node] chạy trên node đang host Pod.
# ==============================================================================

echo "Lab 1.1: Bắt đầu khám phá Network Namespace!"
echo "Lưu ý: Mở file này ra và copy/paste từng lệnh để hiểu rõ cơ chế."

# ------------------------------------------------------------------------------
# Bước 0: Cài đặt CNI Plugin (Flannel) [Control Plane]
# (Bắt buộc chạy nếu Cluster từ Module 0 đang NotReady do thiếu CNI)
# ------------------------------------------------------------------------------
# kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# kubectl get nodes -w  # Chờ đến khi tất cả Node chuyển sang trạng thái 'Ready'

# ------------------------------------------------------------------------------
# Bước 1: Tạo Pod thử nghiệm [Control Plane]
# ------------------------------------------------------------------------------
# kubectl run nginx-test --image=nginx --restart=Never
# kubectl get pod nginx-test -o wide
# (Ghi lại IP của Pod và tên Worker Node)

# ------------------------------------------------------------------------------
# Bước 2: SSH vào Worker Node chứa Pod
# ------------------------------------------------------------------------------
# vagrant ssh <worker-node-name>  # Nếu dùng Vagrant
# multipass shell <worker-node-name>  # Nếu dùng Multipass

# ------------------------------------------------------------------------------
# Bước 3: Tìm Container ID và PID của Pod [Worker Node]
# ------------------------------------------------------------------------------
# Liệt kê container
# sudo crictl ps | grep nginx-test

# Lấy Container ID
# CONTAINER_ID=$(sudo crictl ps -q --name nginx-test)
# echo "Container ID: $CONTAINER_ID"

# Lấy PID của process (Dùng jq hoặc python3)
# POD_PID=$(sudo crictl inspect $CONTAINER_ID | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['pid'])")
# echo "PID của Pod: $POD_PID"

# ------------------------------------------------------------------------------
# Bước 4: Xem interface veth từ phía Node [Worker Node]
# ------------------------------------------------------------------------------
# Liệt kê các card mạng trên host
# ip link show

# ------------------------------------------------------------------------------
# Bước 5: Chui vào Network Namespace của Pod [Worker Node]
# ------------------------------------------------------------------------------
# Sử dụng nsenter để chạy lệnh 'ip addr' bên TRONG namespace của Pod
# sudo nsenter -t $POD_PID -n ip addr show

# Xem bảng định tuyến (routing table) của Pod
# sudo nsenter -t $POD_PID -n ip route show

# ------------------------------------------------------------------------------
# Bước 6: Bắt gói tin trực tiếp trên veth pair [Worker Node]
# ------------------------------------------------------------------------------
# Tự động tìm veth interface (tùy thuộc vào CNI, VD: cali*, veth*)
# Cú pháp dưới đây giả định dùng mạng bridge cơ bản (cni0)
# VETH=$(ip link show | grep -B1 "master cni0" | grep veth | awk '{print $2}' | tr -d ':' | head -n 1)
# echo "Veth interface: $VETH"

# Bắt gói tin (Để lệnh này chạy và mở terminal khác để ping)
# sudo tcpdump -i $VETH -nn

# ------------------------------------------------------------------------------
# Bước 7: Tạo traffic thử nghiệm [Control Plane - Terminal số 2]
# ------------------------------------------------------------------------------
# Gửi request vào Pod để tcpdump bên kia bắt được gói tin
# kubectl exec -it nginx-test -- curl localhost

# ------------------------------------------------------------------------------
# Bước 8: Dọn dẹp [Control Plane]
# ------------------------------------------------------------------------------
# kubectl delete pod nginx-test
