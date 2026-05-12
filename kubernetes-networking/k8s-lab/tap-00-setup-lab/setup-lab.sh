#!/usr/bin/env bash
# setup-lab.sh — Khởi tạo K8s lab cluster với Multipass
# Dùng: ./setup-lab.sh [flannel|calico|cilium]
# Mặc định: không cài CNI (cài sau theo từng tập)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/k8s-node.yaml"
CNI="${1:-none}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Preflight checks ────────────────────────────────────────────────────────
command -v multipass &>/dev/null || die "Multipass not installed. Run: brew install multipass"
[[ -f "$CLOUD_INIT" ]] || die "cloud-init file not found: $CLOUD_INIT"

info "Cloud-init: $CLOUD_INIT"
info "CNI: ${CNI}"

# ── Launch VMs in parallel ───────────────────────────────────────────────────
info "Launching 3 VMs (this takes 3-5 minutes)..."

multipass launch 26.04 \
  --name k8s-master \
  --cpus 2 --memory 4G --disk 30G \
  --cloud-init "$CLOUD_INIT" &

multipass launch 26.04 \
  --name k8s-worker1 \
  --cpus 2 --memory 2G --disk 20G \
  --cloud-init "$CLOUD_INIT" &

multipass launch 26.04 \
  --name k8s-worker2 \
  --cpus 2 --memory 2G --disk 20G \
  --cloud-init "$CLOUD_INIT" &

wait
info "All VMs launched!"

# ── Wait for cloud-init on each node ────────────────────────────────────────
info "Waiting for cloud-init to complete on all nodes..."
for NODE in k8s-master k8s-worker1 k8s-worker2; do
  echo -n "  → $NODE: "
  multipass exec "$NODE" -- cloud-init status --wait
done

# ── Verify installation ──────────────────────────────────────────────────────
info "Verifying K8s tools..."
multipass exec k8s-master -- kubelet --version
multipass exec k8s-master -- kubeadm version -o short
multipass exec k8s-master -- systemctl is-active containerd

# ── Init cluster on master ───────────────────────────────────────────────────
MASTER_IP=$(multipass info k8s-master | awk '/IPv4/ {print $2}')
info "Master IP: $MASTER_IP"
info "Running kubeadm init..."

multipass exec k8s-master -- sudo kubeadm init \
  --apiserver-advertise-address="$MASTER_IP" \
  --pod-network-cidr=10.244.0.0/16 \
  --node-name=k8s-master

# Setup kubeconfig on master
multipass exec k8s-master -- bash -c '
  mkdir -p $HOME/.kube
  sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
  echo "export KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
'

# ── Join workers ─────────────────────────────────────────────────────────────
info "Joining workers..."
JOIN_CMD=$(multipass exec k8s-master -- sudo kubeadm token create --print-join-command)

multipass exec k8s-worker1 -- sudo $JOIN_CMD &
multipass exec k8s-worker2 -- sudo $JOIN_CMD &
wait

# Label workers
multipass exec k8s-master -- kubectl label node k8s-worker1 node-role.kubernetes.io/worker=worker
multipass exec k8s-master -- kubectl label node k8s-worker2 node-role.kubernetes.io/worker=worker

# ── Copy kubeconfig to macOS host ────────────────────────────────────────────
info "Copying kubeconfig to ~/.kube/k8s-lab-config..."
mkdir -p ~/.kube
multipass exec k8s-master -- cat ~/.kube/config > ~/.kube/k8s-lab-config
sed -i '' "s/127.0.0.1/$MASTER_IP/g" ~/.kube/k8s-lab-config

# ── Install CNI ──────────────────────────────────────────────────────────────
case "$CNI" in
  flannel)
    info "Installing Flannel CNI..."
    multipass exec k8s-master -- kubectl apply -f \
      https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    ;;
  calico)
    info "Installing Calico CNI..."
    multipass exec k8s-master -- kubectl apply -f \
      https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
    ;;
  cilium)
    info "Installing Cilium CNI..."
    multipass exec k8s-master -- bash -c '
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      helm repo add cilium https://helm.cilium.io/
      helm install cilium cilium/cilium \
        --namespace kube-system \
        --set hubble.enabled=true \
        --set hubble.relay.enabled=true \
        --set hubble.ui.enabled=true
    '
    ;;
  none)
    warn "No CNI installed. Install manually when needed:"
    warn "  ./setup-lab.sh flannel   # Tập 6-10"
    warn "  ./setup-lab.sh calico    # Tập 11-26"
    warn "  ./setup-lab.sh cilium    # Tập 27-43"
    ;;
  *)
    die "Unknown CNI: $CNI. Chọn: flannel | calico | cilium | none"
    ;;
esac

# ── Final status ─────────────────────────────────────────────────────────────
echo ""
info "Cluster status:"
KUBECONFIG=~/.kube/k8s-lab-config kubectl get nodes -o wide

echo ""
info "Thêm vào ~/.zshrc:"
echo '  export KUBECONFIG=~/.kube/k8s-lab-config'
echo '  alias k=kubectl'
echo ""
info "Done! Run: export KUBECONFIG=~/.kube/k8s-lab-config"
