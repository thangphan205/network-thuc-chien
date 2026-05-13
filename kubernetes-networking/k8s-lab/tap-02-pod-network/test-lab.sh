#!/bin/bash

# Script tự động kiểm tra bài lab Pod Network & Pause Container (Tập 2)
# Yêu cầu: Chạy trên máy host (macOS/Linux) đã cài Multipass. Cụm K8s đã Ready.
# Dependency trên worker node: python3 (để parse crictl JSON). Ubuntu 22.04+ có sẵn.

echo "=================================================="
echo "🧪 BẮT ĐẦU KIỂM TRA: POD NETWORK & PAUSE CONTAINER"
echo "=================================================="

# Hàm helper
run_cp() {
  multipass exec controlplane -- "$@"
}
run_w1() {
  multipass exec worker1 -- "$@"
}

echo -e "\n[1/5] 📦 KHỞI TẠO POD ĐỂ QUAN SÁT..."
run_cp kubectl run pod-a --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker1"}}' -- sleep infinity >/dev/null 2>&1
run_cp kubectl run pod-b --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker2"}}' -- sleep infinity >/dev/null 2>&1

echo "⏳ Đang chờ 2 Pod khởi tạo..."
run_cp kubectl wait --for=condition=Ready pod/pod-a pod/pod-b --timeout=60s >/dev/null 2>&1

PODA_IP=$(run_cp kubectl get pod pod-a -o jsonpath='{.status.podIP}')
echo "-> pod-a đang chạy trên worker1 với IP: $PODA_IP"

echo -e "\n[2/5] 🕵️‍♂️ TÌM PAUSE CONTAINER TRÊN WORKER1 VÀ DÙNG NSENTER..."
# Lấy ID của pause container (Sandbox ID)
PAUSE_ID=$(run_w1 sudo crictl pods --name pod-a -q)
echo "-> ID của Pause Container: $PAUSE_ID"

# Lấy PID của pause container bằng python3 để parse chuẩn xác
PAUSE_PID=$(run_w1 sudo crictl inspectp $PAUSE_ID | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['pid'])")
echo "-> PID của Pause Container: $PAUSE_PID"

echo "Chạy lệnh 'ip addr' bên trong Pod từ Node bằng nsenter:"
run_w1 sudo nsenter -t $PAUSE_PID -n ip addr | grep inet | grep -v "127.0.0.1"

echo -e "\n[3/5] 🔗 KIỂM TRA VETH PAIR VÀ CNI0 BRIDGE TRÊN WORKER1..."
echo "Lệnh: ip link show master cni0"
run_w1 ip link show master cni0

echo "Kiểm tra route /16 trong Pod (CNI anchor route):"
ROUTE_16=$(run_w1 sudo nsenter -t $PAUSE_PID -n ip route | grep "10.244.0.0/16")
if [ -n "$ROUTE_16" ]; then
  echo "-> ✅ Route /16 tồn tại: $ROUTE_16"
else
  echo "-> ❌ THIẾU route 10.244.0.0/16 trong Pod!"
fi

echo -e "\n[4/5] 📡 PING TỪ WORKER1 VÀO POD (NGUYÊN TẮC 2)..."
echo "Ping từ worker1 tới $PODA_IP:"
run_w1 ping -c 2 $PODA_IP

echo -e "\n[5/5] 💥 THÍ NGHIỆM CRASH APP CONTAINER (ANCHOR TEST)..."
APP_ID=$(run_cp kubectl get pod pod-a -o jsonpath='{.status.containerStatuses[0].containerID}' | cut -d/ -f3)
echo "-> ID của App Container: $APP_ID"

echo "Đang kill App Container để giả lập crash..."
run_w1 sudo crictl stop $APP_ID >/dev/null 2>&1

echo "Ngay lập tức kiểm tra lại IP của pod-a:"
NEW_PODA_IP=$(run_cp kubectl get pod pod-a -o jsonpath='{.status.podIP}')
echo "-> IP mới của pod-a: $NEW_PODA_IP (Phải giống hệt IP cũ: $PODA_IP)"

echo "Chờ Kubelet restart lại Pod..."
sleep 5
run_cp kubectl get pod pod-a

echo "=================================================="
echo "✅ HOÀN TẤT BÀI KIỂM TRA TẬP 2."
echo "Bạn có thể xóa Pods bằng lệnh: multipass exec controlplane -- kubectl delete pod pod-a pod-b"
echo "=================================================="
