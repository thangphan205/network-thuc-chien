#!/bin/bash

# Script tự động kiểm tra trạng thái bài lab K8s Network Model (Tập 1)
# Yêu cầu: Chạy trên máy host (macOS/Linux) đã cài Multipass

echo "=================================================="
echo "🧪 BẮT ĐẦU KIỂM TRA: KUBERNETES NETWORK MODEL (TẬP 1)"
echo "=================================================="

# Hàm helper chạy lệnh trên controlplane
run_cp() {
  multipass exec controlplane -- "$@"
}

echo -e "\n[1/5] 🧐 KỂM TRA TRẠNG THÁI CỤM KHI CHƯA CÓ CNI..."
echo "Lệnh: kubectl get nodes"
run_cp kubectl get nodes
echo "-> Các Node thường sẽ ở trạng thái 'NotReady' do chưa cài CNI."

echo -e "\n[2/5] 📦 TẠO THỬ MỘT POD ĐỂ QUAN SÁT..."
run_cp kubectl run test-pod --image=nginx --restart=Never >/dev/null 2>&1
sleep 3
echo "Lệnh: kubectl get pod test-pod"
run_cp kubectl get pod test-pod
echo "-> Pod thường sẽ kẹt ở 'Pending' vì Node NotReady."

echo -e "\n[3/5] 🔌 CÀI ĐẶT FLANNEL CNI..."
echo "Đang áp dụng Flannel manifest..."
run_cp kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml >/dev/null 2>&1

echo "⏳ Đang chờ các Node chuyển sang trạng thái Ready (có thể mất 30s-1m)..."
run_cp kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo -e "\n[4/5] 🚀 KIỂM TRA LẠI SAU KHI CÓ CNI..."
echo "Lệnh: kubectl get nodes"
run_cp kubectl get nodes
echo "-> Node đã Ready!"

echo "Lệnh: kubectl get pod test-pod"
run_cp kubectl wait --for=condition=Ready pod/test-pod --timeout=60s >/dev/null 2>&1
run_cp kubectl get pod test-pod -o wide
echo "-> Pod đã Running và được cấp IP!"

echo -e "\n[5/5] 🔍 QUAN SÁT DẤU VẾT NETWORK DO CNI TẠO RA TRÊN CONTROLPLANE..."
echo "Lệnh: ip link show | grep -E 'cni0|flannel.1'"
run_cp ip link show | grep -E "cni0|flannel.1" || echo "Đang khởi tạo interface..."

echo -e "\nLệnh: ip route show | grep -E '10.244|cni0|flannel.1'"
run_cp ip route show | grep -E "10.244|cni0|flannel.1"

echo "=================================================="
echo "✅ HOÀN TẤT KỊCH BẢN TEST TẬP 1."
echo "Bạn có thể dùng lệnh './reset-lab.sh' ở thư mục tap-00 để dọn dẹp cụm."
echo "=================================================="
