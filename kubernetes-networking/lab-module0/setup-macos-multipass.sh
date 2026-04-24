#!/bin/bash

echo "🚀 Kiểm tra công cụ Multipass..."
if ! command -v multipass &> /dev/null
then
    echo "Multipass chưa được cài đặt. Đang tiến hành cài đặt qua Homebrew..."
    brew install --cask multipass
else
    echo "✅ Đã cài đặt Multipass."
fi

echo "🚀 Bắt đầu tạo 3 máy ảo Ubuntu bằng Multipass và tự động cài K8s tools..."

# Tạo Control Plane
echo "[1/3] Đang khởi tạo Control Plane (2 CPUs, 2GB RAM)..."
multipass launch jammy --name controlplane --cpus 2 --memory 2G --disk 10G --cloud-init k8s-cloud-init.yaml

# Tạo Worker 1
echo "[2/3] Đang khởi tạo Worker 1 (1 CPU, 1.5GB RAM)..."
multipass launch jammy --name worker1 --cpus 1 --memory 1536M --disk 10G --cloud-init k8s-cloud-init.yaml

# Tạo Worker 2
echo "[3/3] Đang khởi tạo Worker 2 (1 CPU, 1.5GB RAM)..."
multipass launch jammy --name worker2 --cpus 1 --memory 1536M --disk 10G --cloud-init k8s-cloud-init.yaml

echo "🎉 Hoàn tất! Danh sách các máy ảo:"
multipass list

echo ""
echo "Bạn có thể truy cập vào máy ảo bằng lệnh: multipass shell <tên-máy-ảo>"
echo "Hãy làm theo hướng dẫn trong lab-module0-macos-guide.md để tiếp tục."
