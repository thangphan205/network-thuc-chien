#!/bin/bash
# =====================================================================
# Automated Kubernetes Cluster & Calico CNI Setup Script
# Tập 23: Calico Observability (Prometheus + Grafana + Alertmanager)
# Kênh: Network Thực Chiến (youtube.com/@NetworkThucChien)
# =====================================================================

set -euo pipefail

# Đường dẫn cloud-init tương đối
CLOUD_INIT="../tap-00-setup-lab/k8s-cloud-init.yaml"
POD_CIDR="10.244.0.0/16"

echo "===================================================================="
# Phát hiện kiến trúc CPU của máy host
ARCH=$(uname -m)
echo "🔍 Đang tự động nhận diện kiến trúc CPU của bạn..."
sleep 0.5

if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    echo "🍏 PHÁT HIỆN CHIP ARM (Apple Silicon)!"
    MEM_CP="2560M"
    MEM_WK="2048M"
    CPU_CP=2
    CPU_WK=2
else
    echo "💻 PHÁT HIỆN CHIP AMD/INTEL (x86_64)!"
    MEM_CP="2G"
    MEM_WK="1536M"
    CPU_CP=2
    CPU_WK=1
fi
echo "===================================================================="

# ── Kiểm tra tệp cloud-init ───────────────────────────────────────
if [[ ! -f "$CLOUD_INIT" ]]; then
    echo "❌ Lỗi: Không tìm thấy tệp cloud-init tại: $CLOUD_INIT"
    echo "   Vui lòng chạy script từ thư mục tap-23-calico-observability/"
    exit 1
fi

# ── Kiểm tra và cài đặt Multipass ─────────────────────────────────
if ! command -v multipass &>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "📦 Multipass chưa được cài đặt. Đang tự động cài qua Homebrew..."
        brew install --cask multipass
    else
        echo "❌ Lỗi: Không tìm thấy Multipass. Vui lòng cài đặt tại https://multipass.run/"
        exit 1
    fi
fi

# ── Dọn dẹp VM cũ nếu có ──────────────────────────────────────────
for VM in controlplane worker1 worker2; do
    if multipass list 2>/dev/null | grep -q "$VM"; then
        echo "⚠️  Máy ảo '$VM' đã tồn tại."
        read -r -p "   Bạn có muốn XOÁ HOÀN TOÀN và tạo lại cụm lab mới? (y/N): " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "🔥 Đang xoá máy ảo '$VM'..."
            multipass stop "$VM" 2>/dev/null || true
            multipass delete "$VM" 2>/dev/null || true
            multipass purge
        else
            echo "❌ Đã huỷ quá trình setup. Sử dụng cụm hiện tại."
            exit 0
        fi
    fi
done

# ── Cấu hình Driver macOS tối ưu ──────────────────────────────────
if [[ "$OSTYPE" == "darwin"* ]]; then
    CURRENT_DRIVER=$(multipass get local.driver 2>/dev/null || echo "unknown")
    if [[ "$CURRENT_DRIVER" != "qemu" && "$CURRENT_DRIVER" != "virtualization" ]]; then
        echo "🔧 Cấu hình driver ảo hoá 'qemu' tối ưu..."
        multipass set local.driver=qemu
    fi
fi

# ─────────────────────────────────────────────────────────────────
# BƯỚC 1: Khởi chạy các máy ảo VM
# ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━ [1/6] Đang khởi chạy 3 máy ảo Ubuntu 26.04 qua Multipass ━━━"

multipass launch 26.04 --name controlplane --cpus "$CPU_CP" --memory "$MEM_CP" --disk 15G --cloud-init "$CLOUD_INIT"
echo "✅ VM controlplane đã sẵn sàng"

multipass launch 26.04 --name worker1 --cpus "$CPU_WK" --memory "$MEM_WK" --disk 15G --cloud-init "$CLOUD_INIT"
echo "✅ VM worker1 đã sẵn sàng"

multipass launch 26.04 --name worker2 --cpus "$CPU_WK" --memory "$MEM_WK" --disk 15G --cloud-init "$CLOUD_INIT"
echo "✅ VM worker2 đã sẵn sàng"

# ─────────────────────────────────────────────────────────────────
# BƯỚC 2: Chờ cloud-init hoàn thành cài package K8s
# ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━ [2/6] Đang chờ cấu hình tự động (cloud-init) hoàn tất ━━━"
echo "⏳ Bước này mất khoảng 2-4 phút tùy thuộc vào mạng của bạn..."

multipass exec controlplane -- sudo cloud-init status --wait
echo "✅ Cấu hình controlplane OK!"
multipass exec worker1 -- sudo cloud-init status --wait
echo "✅ Cấu hình worker1 OK!"
multipass exec worker2 -- sudo cloud-init status --wait
echo "✅ Cấu hình worker2 OK!"

# ─────────────────────────────────────────────────────────────────
# BƯỚC 3: Khởi tạo cụm Kubernetes qua Kubeadm
# ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━ [3/6] Đang khởi tạo Kubernetes Control Plane ━━━━━━━━━━━━━━━━"

CONTROL_PLANE_IP=$(multipass info controlplane | grep IPv4 | awk '{print $2}')
echo "   Địa chỉ IP Control Plane: $CONTROL_PLANE_IP"

multipass exec controlplane -- bash -s <<EOF
set -e
sudo kubeadm init \
    --apiserver-advertise-address=${CONTROL_PLANE_IP} \
    --pod-network-cidr=${POD_CIDR}

# Cấu hình kubeconfig
mkdir -p \$HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

# Gán role worker cho chính controlplane hiển thị trực quan
kubectl label node controlplane node-role.kubernetes.io/control-plane= 2>/dev/null || true
EOF
echo "✅ Khởi tạo Control Plane thành công!"

# ─────────────────────────────────────────────────────────────────
# BƯỚC 4: Kết nối các Worker Nodes vào cụm
# ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━ [4/6] Đang kết nối (join) các Worker Nodes vào cụm ━━━━━━━━━━"

JOIN_CMD=$(multipass exec controlplane -- sudo kubeadm token create --print-join-command 2>/dev/null)

multipass exec worker1 -- sudo bash -c "$JOIN_CMD"
echo "✅ worker1 kết nối thành công"

multipass exec worker2 -- sudo bash -c "$JOIN_CMD"
echo "✅ worker2 kết nối thành công"

# Gán role cho các Node Worker
multipass exec controlplane -- bash -c "
kubectl label node worker1 node-role.kubernetes.io/worker= 2>/dev/null || true
kubectl label node worker2 node-role.kubernetes.io/worker= 2>/dev/null || true
"
echo "✅ Đã gán nhãn vai trò Node!"

# ─────────────────────────────────────────────────────────────────
# BƯỚC 5: Cài đặt Calico CNI
# ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━ [5/6] Đang cài đặt Calico CNI qua Tigera Operator ━━━━━━━━━━━"

multipass exec controlplane -- bash -s <<EOF
set -e
# Cài đặt Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml

# Đợi Operator Pod chạy
echo "⏳ Đang chờ Tigera Operator chạy..."
kubectl -n tigera-operator wait --for=condition=Ready pod -l k8s-app=tigera-operator --timeout=60s

# Áp dụng Custom Resource cài mạng Calico
kubectl create -f - <<'CR_EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
CR_EOF
EOF
echo "✅ Đã deploy Calico CNI"

# ─────────────────────────────────────────────────────────────────
# BƯỚC 6: Bật Felix Metrics và Cài đặt Helm
# ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━ [6/6] Kích hoạt Felix Metrics & Cài đặt Helm trên Node ━━━━━━"

multipass exec controlplane -- bash -s <<EOF
set -e

# Bật Felix Metrics endpoint (Port 9091)
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"prometheusMetricsEnabled": true}}'

# Cài đặt Helm
if ! command -v helm &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
EOF

echo ""
echo "===================================================================="
echo " 🎉 CỤM KUBERNETES & CALICO LAB ĐÃ SẴN SÀNG!"
echo "===================================================================="
echo " - Hệ điều hành máy ảo: Ubuntu 26.04 LTS"
echo " - Số lượng Node:       3 (controlplane, worker1, worker2)"
echo " - Calico CNI:          Đã cài (Pod CIDR 10.244.0.0/16)"
echo " - Felix Metrics:       Đã kích hoạt (Port 9091)"
echo " - Helm CLI:            Đã cài đặt thành công"
echo ""
echo " Bạn có thể bắt đầu ngay bài lab bằng cách chạy lệnh:"
# Chỉ dẫn rõ cách truy cập
echo "   multipass shell controlplane"
echo "   kubectl get nodes"
echo ""
echo " Tiến hành tiếp theo từ Thực nghiệm 2 (Telegram Bot) trong lab-guide.md"
echo "===================================================================="
