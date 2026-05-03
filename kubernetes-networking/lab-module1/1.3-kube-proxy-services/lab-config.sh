#!/usr/bin/env bash
# =============================================================================
# Lab 1.3: Kube-proxy & Services
# Script tự động hóa việc setup môi trường lab
# Chạy: bash lab-config.sh [setup|teardown|switch-ipvs|switch-nftables]
# =============================================================================
set -euo pipefail

ACTION="${1:-setup}"

# Colors
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# =============================================================================
setup() {
  info "=== Lab 1.3: Triển khai ứng dụng demo ==="

  kubectl apply -f - <<'EOF'
---
# Deployment: 3 replicas để test load balancing
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab13-web
  namespace: default
  labels:
    lab: "1.3"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: lab13-web
  template:
    metadata:
      labels:
        app: lab13-web
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
        # Mỗi Pod in hostname của mình → dễ verify load balancing
        lifecycle:
          postStart:
            exec:
              command: ["/bin/sh", "-c",
                "echo '<h1>Pod: '$(hostname)'</h1>' > /usr/share/nginx/html/index.html"]
---
# ClusterIP Service
apiVersion: v1
kind: Service
metadata:
  name: lab13-clusterip
  namespace: default
  labels:
    lab: "1.3"
spec:
  selector:
    app: lab13-web
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
---
# NodePort Service
apiVersion: v1
kind: Service
metadata:
  name: lab13-nodeport
  namespace: default
  labels:
    lab: "1.3"
spec:
  selector:
    app: lab13-web
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
  type: NodePort
  externalTrafficPolicy: Cluster   # Thay đổi thành Local để test
---
# Debug pod: netshoot để chạy các lệnh mạng
apiVersion: v1
kind: Pod
metadata:
  name: lab13-netshoot
  namespace: default
  labels:
    lab: "1.3"
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

  info "Đợi các Pod sẵn sàng..."
  kubectl wait --for=condition=Ready pod -l app=lab13-web --timeout=120s
  kubectl wait --for=condition=Ready pod/lab13-netshoot --timeout=60s

  CLUSTER_IP=$(kubectl get svc lab13-clusterip -o jsonpath='{.spec.clusterIP}')
  NODE_PORT=30080
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[0].address}' 2>/dev/null || \
            kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')

  echo ""
  info "=== Môi trường Lab sẵn sàng ==="
  echo -e "${GREEN}ClusterIP Service:${NC} ${CLUSTER_IP}:80"
  echo -e "${GREEN}NodePort Service:${NC}  ${NODE_IP}:${NODE_PORT}"
  echo ""
  warn "=== Bước tiếp theo ==="
  echo "1. Xem iptables chains:"
  echo "   sudo iptables -t nat -L KUBE-SERVICES -n --line-numbers | head -20"
  echo ""
  echo "2. Tìm chain của ClusterIP ${CLUSTER_IP}:"
  echo "   sudo iptables -t nat -L -n | grep ${CLUSTER_IP}"
  echo ""
  echo "3. Test ClusterIP từ netshoot pod:"
  echo "   kubectl exec -it lab13-netshoot -- curl ${CLUSTER_IP}"
  echo ""
  echo "4. Gọi nhiều lần để thấy load balancing:"
  echo "   for i in \$(seq 1 6); do kubectl exec lab13-netshoot -- curl -s ${CLUSTER_IP}; done"
}

# =============================================================================
teardown() {
  info "Dọn dẹp Lab 1.3..."
  kubectl delete pod,svc,deployment -l lab=1.3 --ignore-not-found
  info "Done!"
}

# =============================================================================
switch_ipvs() {
  info "=== Chuyển kube-proxy sang IPVS mode ==="
  warn "Lệnh này cần chạy trên Control Plane node với quyền root!"

  # Kiểm tra kernel module
  info "Kiểm tra kernel modules cần thiết cho IPVS..."
  for mod in ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack; do
    if lsmod | grep -q "$mod"; then
      echo -e "  ${GREEN}✅${NC} $mod"
    else
      echo -e "  ${YELLOW}⚠️${NC} $mod (chưa load)"
      echo "  → Chạy: sudo modprobe $mod"
    fi
  done

  echo ""
  info "Patch kube-proxy ConfigMap sang IPVS mode:"
  echo '---'
  echo 'kubectl -n kube-system get cm kube-proxy -o yaml | \
  sed "s/mode: \"\"/mode: \"ipvs\"/" | \
  kubectl apply -f -'
  echo ""
  echo "# Sau đó restart kube-proxy DaemonSet:"
  echo "kubectl -n kube-system rollout restart daemonset kube-proxy"
  echo ""
  echo "# Verify bằng ipvsadm:"
  echo "sudo ipvsadm -Ln"
}

# =============================================================================
switch_nftables() {
  info "=== Chuyển kube-proxy sang nftables mode (K8s v1.33+) ==="

  kubectl -n kube-system get cm kube-proxy -o yaml | \
    grep -A5 "mode:" || true

  echo ""
  info "Patch command:"
  cat <<'EOF'
kubectl -n kube-system patch cm kube-proxy --type=merge -p '
{
  "data": {
    "config.conf": "apiVersion: kubeproxy.config.k8s.io/v1alpha1\nkind: KubeProxyConfiguration\nmode: nftables\n"
  }
}'
kubectl -n kube-system rollout restart daemonset kube-proxy

# Verify:
kubectl -n kube-system logs -l k8s-app=kube-proxy | grep -i nftables
EOF
}

# =============================================================================
case "$ACTION" in
  setup)          setup ;;
  teardown)       teardown ;;
  switch-ipvs)    switch_ipvs ;;
  switch-nftables) switch_nftables ;;
  *)
    echo "Usage: $0 [setup|teardown|switch-ipvs|switch-nftables]"
    exit 1
    ;;
esac
