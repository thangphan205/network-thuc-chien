#!/usr/bin/env bash
# reset-lab.sh — Reset K8s cluster (giữ VMs) hoặc xóa hoàn toàn
# Dùng:
#   ./reset-lab.sh          — reset cluster, giữ VMs (để đổi CNI)
#   ./reset-lab.sh --purge  — xóa toàn bộ VMs

set -euo pipefail

PURGE=false
[[ "${1:-}" == "--purge" ]] && PURGE=true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

NODES=(k8s-master k8s-worker1 k8s-worker2)

if $PURGE; then
  warn "Xóa toàn bộ VMs..."
  multipass delete "${NODES[@]}" 2>/dev/null || true
  multipass purge
  rm -f ~/.kube/k8s-lab-config
  info "Purge done. Recreate: ./setup-lab.sh"
else
  info "Reset cluster (giữ VMs)..."
  for NODE in "${NODES[@]}"; do
    echo -n "  → resetting $NODE: "
    multipass exec "$NODE" -- sudo kubeadm reset -f 2>/dev/null || echo "skip (not joined)"
    multipass exec "$NODE" -- sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet 2>/dev/null || true
    echo "done"
  done

  info "Cluster reset. Reinit với:"
  echo "  MASTER_IP=\$(multipass info k8s-master | awk '/IPv4/ {print \$2}')"
  echo "  multipass exec k8s-master -- sudo kubeadm init \\"
  echo "    --apiserver-advertise-address=\$MASTER_IP \\"
  echo "    --pod-network-cidr=10.244.0.0/16 \\"
  echo "    --node-name=k8s-master"
fi
