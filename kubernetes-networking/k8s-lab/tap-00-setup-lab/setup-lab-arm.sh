#!/bin/bash

# ==========================================
# Script Setup Lab K8s 3 Nodes - Kiến trúc ARM
# Tối ưu hóa cho Apple Silicon M1/M2/M3/M4 (macOS)
# Kênh: Network Thực Chiến (youtube.com/@NetworkThucChien)
# ==========================================

set -e

echo "============================================================"
echo "🚀 KHỞI TẠO MÔI TRƯỜNG K8S LAB - KIẾN TRÚC ARM (ARM64) 🚀"
echo "============================================================"

# 1. Kiểm tra kiến trúc CPU của Host
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" && "$ARCH" != "aarch64" ]]; then
    echo "❌ LỖI KIẾN TRÚC VẬT LÝ KHÔNG PHÙ HỢP!"
    echo "⚠️  Máy của bạn đang chạy chip: $ARCH (AMD/Intel)."
    echo "👉 Hãy sử dụng script dành riêng cho AMD/Intel: ./setup-lab-amd.sh"
    exit 1
fi

echo "✅ Xác thực kiến trúc phần cứng thành công: $ARCH (ARM64)"

# 2. Kiểm tra và Cài đặt Multipass
echo "🚀 Kiểm tra công cụ Multipass..."
if ! command -v multipass &> /dev/null
then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Multipass chưa được cài đặt. Đang tiến hành cài đặt qua Homebrew..."
        brew install --cask multipass
    else
        echo "❌ Lỗi: Không tìm thấy Multipass. Vui lòng cài đặt Multipass tại https://multipass.run trước khi tiếp tục."
        exit 1
    fi
else
    echo "✅ Đã cài đặt Multipass."
fi

# 3. Tối ưu cấu hình Driver ảo hóa trên macOS ARM
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍏 Phát hiện hệ điều hành macOS trên chip Apple Silicon."
    CURRENT_DRIVER=$(multipass get local.driver 2>/dev/null || echo "unknown")
    echo "ℹ️  Driver ảo hóa hiện tại: $CURRENT_DRIVER"
    if [[ "$CURRENT_DRIVER" != "qemu" && "$CURRENT_DRIVER" != "virtualization" ]]; then
        echo "🔧 Đang cấu hình driver 'qemu' (hoặc 'virtualization') tối ưu cho chip ARM..."
        multipass set local.driver=qemu
        echo "✅ Đã cập nhật driver sang 'qemu'."
    fi
fi

echo "🚀 Bắt đầu tạo 3 máy ảo Ubuntu 26.04 (ARM64) bằng Multipass..."
echo "💡 Hệ thống sẽ tự động cấu hình container runtime (containerd), kubeadm và kubelet qua cloud-init."

# Tạo Control Plane
echo "------------------------------------------------------------"
echo "👉 [1/3] Đang khởi tạo Control Plane (controlplane: 2 CPUs, 2GB RAM, 10GB Disk)..."
multipass launch 26.04 --name controlplane --cpus 2 --memory 2G --disk 10G --cloud-init k8s-cloud-init.yaml

# Tạo Worker 1
echo "------------------------------------------------------------"
echo "👉 [2/3] Đang khởi tạo Worker 1 (worker1: 1 CPU, 1.5GB RAM, 10GB Disk)..."
multipass launch 26.04 --name worker1 --cpus 1 --memory 1536M --disk 10G --cloud-init k8s-cloud-init.yaml

# Tạo Worker 2
echo "------------------------------------------------------------"
echo "👉 [3/3] Đang khởi tạo Worker 2 (worker2: 1 CPU, 1.5GB RAM, 10GB Disk)..."
multipass launch 26.04 --name worker2 --cpus 1 --memory 1536M --disk 10G --cloud-init k8s-cloud-init.yaml

echo "------------------------------------------------------------"
echo "⏳ Đang chờ quá trình cài đặt ngầm (cloud-init) hoàn tất trên các node..."
echo "💡 Bước này có thể mất 3-5 phút tùy thuộc vào tốc độ internet của bạn để tải các gói K8s."

multipass exec controlplane -- sudo cloud-init status --wait
echo "✅ Node [controlplane] sẵn sàng!"

multipass exec worker1 -- sudo cloud-init status --wait
echo "✅ Node [worker1] sẵn sàng!"

multipass exec worker2 -- sudo cloud-init status --wait
echo "✅ Node [worker2] sẵn sàng!"

echo "============================================================"
echo "🎉 HOÀN THÀNH SETUP LAB MÁY ẢO CHO CHIP ARM!"
echo "============================================================"
multipass list

echo ""
echo "👉 Bước tiếp theo: hãy theo dõi file 'lab-guide.md' để thực hiện:"
echo "   1. multipass shell controlplane"
echo "   2. Khởi tạo kubeadm init"
echo "   3. Cài đặt CNI (Flannel/Calico/Cilium)"
