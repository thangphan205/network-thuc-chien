#!/usr/bin/env bash
# =============================================================================
# Lab 1.4: DNS trong Kubernetes & Thuế "ndots"
# Script tự động hóa môi trường lab
# Chạy: bash lab-config.sh [setup|teardown|install-nodelocaldns|measure-dns]
# =============================================================================
set -euo pipefail

ACTION="${1:-setup}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

# =============================================================================
setup() {
  info "=== Lab 1.4: Triển khai môi trường DNS lab ==="

  kubectl apply -f - <<'EOF'
---
# App backend để test Service DNS resolution
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab14-backend
  namespace: default
  labels:
    lab: "1.4"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: lab14-backend
  template:
    metadata:
      labels:
        app: lab14-backend
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: lab14-backend
  namespace: default
  labels:
    lab: "1.4"
spec:
  selector:
    app: lab14-backend
  ports:
  - port: 80
    targetPort: 80
---
# Headless Service - DNS trả về Pod IP trực tiếp
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: lab14-db
  namespace: default
  labels:
    lab: "1.4"
spec:
  serviceName: lab14-db-headless
  replicas: 2
  selector:
    matchLabels:
      app: lab14-db
  template:
    metadata:
      labels:
        app: lab14-db
    spec:
      containers:
      - name: db
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: lab14-db-headless
  namespace: default
  labels:
    lab: "1.4"
spec:
  clusterIP: None        # ← Headless!
  selector:
    app: lab14-db
  ports:
  - port: 80
    targetPort: 80
---
# Debug pod với cấu hình ndots tùy chỉnh
apiVersion: v1
kind: Pod
metadata:
  name: lab14-debug-default
  namespace: default
  labels:
    lab: "1.4"
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
  # Giữ nguyên ndots:5 mặc định để quan sát vấn đề
---
apiVersion: v1
kind: Pod
metadata:
  name: lab14-debug-optimized
  namespace: default
  labels:
    lab: "1.4"
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
  dnsConfig:
    options:
    - name: ndots
      value: "2"   # ← Đã tối ưu, so sánh với pod trên
EOF

  info "Đợi các resource sẵn sàng..."
  kubectl wait --for=condition=Ready pod -l app=lab14-backend --timeout=120s
  kubectl wait --for=condition=Ready pod/lab14-debug-default --timeout=60s
  kubectl wait --for=condition=Ready pod/lab14-debug-optimized --timeout=60s

  CLUSTER_DNS=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')
  CLUSTER_IP=$(kubectl get svc lab14-backend -o jsonpath='{.spec.clusterIP}')

  echo ""
  info "=== Môi trường Lab sẵn sàng ==="
  echo ""
  step "Bước 1: Xem resolv.conf mặc định (ndots:5)"
  echo "  kubectl exec lab14-debug-default -- cat /etc/resolv.conf"
  echo ""
  step "Bước 2: So sánh resolv.conf đã tối ưu (ndots:2)"
  echo "  kubectl exec lab14-debug-optimized -- cat /etc/resolv.conf"
  echo ""
  step "Bước 3: Đếm DNS queries khi truy cập domain ngoại"
  echo "  kubectl exec lab14-debug-default -- nslookup google.com"
  echo "  # Dùng tcpdump để đếm: xem lab-guide.md"
  echo ""
  step "Bước 4: Query Headless Service"
  echo "  kubectl exec lab14-debug-default -- nslookup lab14-db-headless.default.svc.cluster.local"
  echo "  # Phải thấy 2 IP Pod khác nhau!"
  echo ""
  step "Bước 5: Query ClusterIP Service"
  echo "  kubectl exec lab14-debug-default -- nslookup lab14-backend.default.svc.cluster.local"
  echo "  # Phải thấy 1 ClusterIP: ${CLUSTER_IP}"
}

# =============================================================================
teardown() {
  info "Dọn dẹp Lab 1.4..."
  kubectl delete pod,svc,deployment,statefulset -l lab=1.4 --ignore-not-found
  info "Done!"
}

# =============================================================================
install_nodelocaldns() {
  info "=== Cài đặt NodeLocal DNSCache ==="
  warn "Đây là thao tác cluster-wide, cần quyền cluster-admin"

  KUBE_DNS_SVC_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')
  LOCALDNS_IP="169.254.20.10"

  info "CoreDNS ClusterIP: ${KUBE_DNS_SVC_IP}"
  info "NodeLocal DNSCache IP: ${LOCALDNS_IP}"

  # Download manifest
  info "Download NodeLocal DNSCache manifest..."
  curl -sL "https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml" \
    | sed "s/__PILLAR__LOCAL__DNS__/${LOCALDNS_IP}/g" \
    | sed "s/__PILLAR__DNS__DOMAIN__/cluster.local/g" \
    | sed "s/__PILLAR__DNS__SERVER__/${KUBE_DNS_SVC_IP}/g" \
    | kubectl apply -f -

  info "Đợi NodeLocal DNSCache DaemonSet sẵn sàng..."
  kubectl -n kube-system rollout status daemonset node-local-dns --timeout=120s

  echo ""
  info "=== Verify NodeLocal DNSCache ==="
  echo "  # Kiểm tra DaemonSet:"
  echo "  kubectl -n kube-system get ds node-local-dns"
  echo ""
  echo "  # Sau khi cài, Pod mới sẽ dùng ${LOCALDNS_IP} làm DNS server"
  echo "  # Kiểm tra resolv.conf của Pod mới:"
  echo "  kubectl exec lab14-debug-default -- cat /etc/resolv.conf"
}

# =============================================================================
measure_dns() {
  info "=== Đo số lượng DNS queries (trước khi optimize) ==="
  warn "Cần tcpdump trên Node, hoặc dùng Hubble/Inspektor Gadget"

  echo ""
  info "Cách 1: Dùng netshoot tcpdump trong Pod riêng"
  echo "  # Terminal 1: Bắt DNS traffic"
  echo "  kubectl exec lab14-debug-default -- tcpdump -i eth0 -n port 53 -c 20"
  echo ""
  echo "  # Terminal 2: Trigger DNS lookup"
  echo "  kubectl exec lab14-debug-default -- curl -s https://google.com -o /dev/null"
  echo ""
  info "Cách 2: Dùng CoreDNS metrics (nếu Prometheus đã cài)"
  echo "  kubectl -n kube-system port-forward svc/kube-dns 9153:9153 &"
  echo "  curl localhost:9153/metrics | grep coredns_dns_requests_total"
}

# =============================================================================
case "$ACTION" in
  setup)                  setup ;;
  teardown)               teardown ;;
  install-nodelocaldns)   install_nodelocaldns ;;
  measure-dns)            measure_dns ;;
  *)
    echo "Usage: $0 [setup|teardown|install-nodelocaldns|measure-dns]"
    exit 1
    ;;
esac
