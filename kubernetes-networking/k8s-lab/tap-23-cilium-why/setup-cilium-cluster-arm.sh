#!/bin/bash
# =============================================================
# Setup Cilium Production Cluster — Apple Silicon (ARM64)
# Tập 23–40: Nền tảng cho toàn bộ Cilium series
# Kênh: Network Thực Chiến
# =============================================================
set -euo pipefail

CLI_ARCH="arm64"
CLOUD_INIT="../tap-00-setup-lab/k8s-cloud-init.yaml"
POD_CIDR="10.244.0.0/16"
K8S_PORT="6443"

echo "============================================================"
echo " CILIUM PRODUCTION CLUSTER SETUP — Apple Silicon (ARM64)"
echo "============================================================"

# ── Kiểm tra kiến trúc ──────────────────────────────────────
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" && "$ARCH" != "aarch64" ]]; then
    echo "❌ Chip không phải ARM64 (detected: $ARCH)"
    echo "   Dùng: ./setup-cilium-cluster-amd.sh"
    exit 1
fi

# ── Kiểm tra cloud-init file ────────────────────────────────
if [[ ! -f "$CLOUD_INIT" ]]; then
    echo "❌ Không tìm thấy $CLOUD_INIT"
    echo "   Chạy script này từ thư mục tap-23-cilium-why/"
    exit 1
fi

# ── Kiểm tra multipass ──────────────────────────────────────
if ! command -v multipass &>/dev/null; then
    echo "📦 Cài Multipass qua Homebrew..."
    brew install --cask multipass
fi

# ── Kiểm tra VMs cũ ─────────────────────────────────────────
for VM in controlplane worker1 worker2; do
    if multipass list 2>/dev/null | grep -q "$VM"; then
        echo "⚠️  VM '$VM' đã tồn tại."
        read -r -p "   Xóa và tạo lại? (y/N): " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            multipass stop "$VM" 2>/dev/null || true
            multipass delete "$VM" 2>/dev/null || true
            multipass purge
        else
            echo "   Bỏ qua. Dùng cluster hiện có."
            exit 0
        fi
    fi
done

# ── Cấu hình qemu driver tối ưu cho ARM ─────────────────────
CURRENT_DRIVER=$(multipass get local.driver 2>/dev/null || echo "unknown")
if [[ "$CURRENT_DRIVER" != "qemu" && "$CURRENT_DRIVER" != "virtualization" ]]; then
    echo "🔧 Cấu hình QEMU driver cho Apple Silicon..."
    multipass set local.driver=qemu
fi

# ────────────────────────────────────────────────────────────
# BƯỚC 1: Tạo VMs
# ────────────────────────────────────────────────────────────
echo ""
echo "━━━ [1/7] Tạo 3 VMs Ubuntu 26.04 ━━━━━━━━━━━━━━━━━━━━━━"

multipass launch 26.04 \
    --name controlplane --cpus 2 --memory 2560M --disk 15G \
    --cloud-init "$CLOUD_INIT"
echo "✅ controlplane created"

multipass launch 26.04 \
    --name worker1 --cpus 2 --memory 2048M --disk 15G \
    --cloud-init "$CLOUD_INIT"
echo "✅ worker1 created"

multipass launch 26.04 \
    --name worker2 --cpus 2 --memory 2048M --disk 15G \
    --cloud-init "$CLOUD_INIT"
echo "✅ worker2 created"

# ────────────────────────────────────────────────────────────
# BƯỚC 2: Chờ cloud-init
# ────────────────────────────────────────────────────────────
echo ""
echo "━━━ [2/7] Chờ cloud-init (cài K8s packages) ━━━━━━━━━━━━"
echo "⏳ Có thể mất 3-5 phút..."

multipass exec controlplane -- sudo cloud-init status --wait
echo "✅ controlplane ready"
multipass exec worker1 -- sudo cloud-init status --wait
echo "✅ worker1 ready"
multipass exec worker2 -- sudo cloud-init status --wait
echo "✅ worker2 ready"

# ────────────────────────────────────────────────────────────
# BƯỚC 3: kubeadm init KHÔNG có kube-proxy
# ────────────────────────────────────────────────────────────
echo ""
echo "━━━ [3/7] kubeadm init (--skip-phases=addon/kube-proxy) ━"

CONTROL_PLANE_IP=$(multipass info controlplane | grep IPv4 | awk '{print $2}')
echo "   Control Plane IP: $CONTROL_PLANE_IP"

multipass exec controlplane -- bash -s <<INIT_EOF
set -e
sudo kubeadm init \
    --apiserver-advertise-address=${CONTROL_PLANE_IP} \
    --pod-network-cidr=${POD_CIDR} \
    --skip-phases=addon/kube-proxy

mkdir -p \$HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

kubectl label node controlplane node-role.kubernetes.io/worker= 2>/dev/null || true
echo "✅ kubeadm init done — kube-proxy không được cài"
INIT_EOF

# ────────────────────────────────────────────────────────────
# BƯỚC 4: Join workers
# ────────────────────────────────────────────────────────────
echo ""
echo "━━━ [4/7] Join worker nodes ━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

JOIN_CMD=$(multipass exec controlplane -- \
    sudo kubeadm token create --print-join-command 2>/dev/null)

multipass exec worker1 -- sudo bash -c "$JOIN_CMD"
echo "✅ worker1 joined"

multipass exec worker2 -- sudo bash -c "$JOIN_CMD"
echo "✅ worker2 joined"

multipass exec controlplane -- bash -c "
kubectl label node worker1 node-role.kubernetes.io/worker= 2>/dev/null || true
kubectl label node worker2 node-role.kubernetes.io/worker= 2>/dev/null || true
"

# ────────────────────────────────────────────────────────────
# BƯỚC 5: Cài Helm + Cilium CLI
# ────────────────────────────────────────────────────────────
echo ""
echo "━━━ [5/7] Cài Helm và Cilium CLI ━━━━━━━━━━━━━━━━━━━━━━━"

multipass exec controlplane -- bash -s <<TOOLS_EOF
set -e

# Helm
if ! command -v helm &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
echo "✅ Helm $(helm version --short)"

# Cilium CLI
CILIUM_CLI_VERSION=\$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all \
    "https://github.com/cilium/cilium-cli/releases/download/\${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}"
sha256sum --check "cilium-linux-${CLI_ARCH}.tar.gz.sha256sum"
sudo tar xzvf "cilium-linux-${CLI_ARCH}.tar.gz" --directory /usr/local/bin
rm "cilium-linux-${CLI_ARCH}.tar.gz" "cilium-linux-${CLI_ARCH}.tar.gz.sha256sum"
echo "✅ Cilium CLI \$(cilium version --client | head -1)"

# Hubble CLI
HUBBLE_VERSION=\$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --fail --remote-name-all \
    "https://github.com/cilium/hubble/releases/download/\${HUBBLE_VERSION}/hubble-linux-${CLI_ARCH}.tar.gz{,.sha256sum}"
sha256sum --check "hubble-linux-${CLI_ARCH}.tar.gz.sha256sum"
sudo tar xzvf "hubble-linux-${CLI_ARCH}.tar.gz" --directory /usr/local/bin
rm "hubble-linux-${CLI_ARCH}.tar.gz" "hubble-linux-${CLI_ARCH}.tar.gz.sha256sum"
echo "✅ Hubble CLI \$(hubble version --client | head -1)"
TOOLS_EOF

# ────────────────────────────────────────────────────────────
# BƯỚC 6: Deploy Cilium — Production Mode
# ────────────────────────────────────────────────────────────
echo ""
echo "━━━ [6/7] Deploy Cilium production mode ━━━━━━━━━━━━━━━━"

multipass exec controlplane -- bash -s <<CILIUM_EOF
set -e

helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update

helm install cilium cilium/cilium \
    --namespace kube-system \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost="${CONTROL_PLANE_IP}" \
    --set k8sServicePort="${K8S_PORT}" \
    --set routingMode=native \
    --set autoDirectNodeRoutes=true \
    --set ipam.mode=cluster-pool \
    --set "ipam.operator.clusterPoolIPv4PodCIDRList=${POD_CIDR}" \
    --set ipam.operator.clusterPoolIPv4MaskSize=24 \
    --set bpf.masquerade=true \
    --set socketLB.enabled=true \
    --set encryption.enabled=true \
    --set encryption.type=wireguard \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set hubble.metrics.enableOpenMetrics=true \
    --set "hubble.metrics.enabled={dns,drop,tcp,flow,port-distribution,icmp,httpV2}" \
    --set operator.replicas=1

echo "⏳ Chờ Cilium sẵn sàng..."
cilium status --wait
CILIUM_EOF

# ────────────────────────────────────────────────────────────
# BƯỚC 7: Verify
# ────────────────────────────────────────────────────────────
echo ""
echo "━━━ [7/7] Verify cluster ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

multipass exec controlplane -- bash -s <<VERIFY_EOF
set -e
echo ""
echo "=== Nodes ==="
kubectl get nodes -o wide

echo ""
echo "=== Cilium Pods ==="
kubectl -n kube-system get pods -l k8s-app=cilium -o wide

echo ""
echo "=== kube-proxy (phải KHÔNG có) ==="
kubectl -n kube-system get pods | grep kube-proxy || echo "✅ Không có kube-proxy — đúng rồi!"

echo ""
echo "=== Cilium Status ==="
cilium status | grep -E "KubeProxy|Encryption|Routing|Hubble"

echo ""
echo "=== WireGuard Status ==="
CILIUM_POD=\$(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1)
kubectl -n kube-system exec -it \$CILIUM_POD -- cilium encrypt status 2>/dev/null || echo "(WireGuard keys đang được trao đổi...)"
VERIFY_EOF

echo ""
echo "============================================================"
echo " ✅ CILIUM PRODUCTION CLUSTER SẴN SÀNG!"
echo "============================================================"
echo ""
echo " Cluster:     3 nodes (controlplane, worker1, worker2)"
echo " Cilium:      kube-proxy replacement + native routing"
echo " Encryption:  WireGuard (pod-to-pod)"
echo " Observability: Hubble (relay + UI + metrics)"
echo ""
echo " Bước tiếp theo:"
echo "   multipass shell controlplane"
echo "   kubectl get nodes"
echo "   cilium status"
echo ""
echo " Tiếp tục với lab-guide.md (Thực nghiệm 5+)"
echo "============================================================"
