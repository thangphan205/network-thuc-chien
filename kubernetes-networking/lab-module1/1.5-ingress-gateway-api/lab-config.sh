#!/usr/bin/env bash
# =============================================================================
# Lab 1.5: Ingress & Gateway API
# Chạy: bash lab-config.sh [setup-ingress|setup-gateway|teardown|view-nginx-conf]
# =============================================================================
set -euo pipefail

ACTION="${1:-setup-ingress}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

# =============================================================================
setup_ingress() {
  info "=== Phần 1: Cài ingress-nginx và cấu hình Ingress cổ điển ==="

  # 1. Cài ingress-nginx
  info "Cài ingress-nginx controller..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml

  info "Đợi ingress-nginx sẵn sàng (có thể mất 2-3 phút)..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s

  # 2. Deploy demo apps
  kubectl apply -f - <<'EOF'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v1
  namespace: default
  labels:
    lab: "1.5"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-v1
  template:
    metadata:
      labels:
        app: app-v1
    spec:
      containers:
      - name: web
        image: nginx:alpine
        lifecycle:
          postStart:
            exec:
              command: ["/bin/sh", "-c",
                "echo '<h1>App V1 - /api route</h1>' > /usr/share/nginx/html/index.html"]
---
apiVersion: v1
kind: Service
metadata:
  name: app-v1
  namespace: default
  labels:
    lab: "1.5"
spec:
  selector:
    app: app-v1
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v2
  namespace: default
  labels:
    lab: "1.5"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-v2
  template:
    metadata:
      labels:
        app: app-v2
    spec:
      containers:
      - name: web
        image: nginx:alpine
        lifecycle:
          postStart:
            exec:
              command: ["/bin/sh", "-c",
                "echo '<h1>App V2 - /admin route</h1>' > /usr/share/nginx/html/index.html"]
---
apiVersion: v1
kind: Service
metadata:
  name: app-v2
  namespace: default
  labels:
    lab: "1.5"
spec:
  selector:
    app: app-v2
  ports:
  - port: 80
---
# Ingress cổ điển
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: default
  labels:
    lab: "1.5"
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: demo.lab.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: app-v1
            port:
              number: 80
      - path: /admin
        pathType: Prefix
        backend:
          service:
            name: app-v2
            port:
              number: 80
EOF

  kubectl wait --for=condition=Ready pod -l app=app-v1 --timeout=60s
  kubectl wait --for=condition=Ready pod -l app=app-v2 --timeout=60s

  INGRESS_NODE_PORT=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[0].address}' 2>/dev/null || \
            kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')

  echo ""
  info "=== Ingress sẵn sàng ==="
  echo "Node IP:   ${NODE_IP}"
  echo "Node Port: ${INGRESS_NODE_PORT}"
  echo ""
  step "Test Ingress routing:"
  echo "  curl -H 'Host: demo.lab.local' http://${NODE_IP}:${INGRESS_NODE_PORT}/api"
  echo "  curl -H 'Host: demo.lab.local' http://${NODE_IP}:${INGRESS_NODE_PORT}/admin"
}

# =============================================================================
view_nginx_conf() {
  info "=== Xem nginx.conf được ingress-nginx tự động sinh ra ==="

  NGINX_POD=$(kubectl -n ingress-nginx get pod \
    -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].metadata.name}')

  if [ -z "$NGINX_POD" ]; then
    error "Không tìm thấy ingress-nginx pod. Chạy 'setup-ingress' trước!"
  fi

  echo ""
  info "Pod: ${NGINX_POD}"
  echo ""
  warn "File nginx.conf (phần upstream và server blocks):"
  kubectl -n ingress-nginx exec "${NGINX_POD}" -- cat /etc/nginx/nginx.conf \
    | grep -A 30 'upstream\|server {' | head -80
}

# =============================================================================
setup_gateway() {
  info "=== Phần 2: Cài Gateway API với Cilium ==="
  warn "Cilium phải đã được cài trên cluster (Tập 10-11)"

  # Cài Gateway API CRDs
  info "Cài Gateway API CRDs..."
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

  kubectl apply -f - <<'EOF'
---
# GatewayClass dùng Cilium
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
  labels:
    lab: "1.5"
spec:
  controllerName: io.cilium/gateway-controller
---
# Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: default
  labels:
    lab: "1.5"
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    port: 80
    protocol: HTTP
---
# HTTPRoute: path-based routing
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-httproute
  namespace: default
  labels:
    lab: "1.5"
spec:
  parentRefs:
  - name: demo-gateway
  hostnames:
  - "demo.lab.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: app-v1
      port: 80
      weight: 90       # 90% traffic ke V1
    - name: app-v2
      port: 80
      weight: 10       # 10% traffic ke V2 (Canary!)
  - matches:
    - path:
        type: PathPrefix
        value: /admin
    backendRefs:
    - name: app-v2
      port: 80
EOF

  echo ""
  info "=== Gateway API resources đã apply ==="
  echo "  kubectl get gateway,httproute -n default"
}

# =============================================================================
teardown() {
  info "Dọn dẹp Lab 1.5..."
  kubectl delete ingress,httproute,gateway,gatewayclass -l lab=1.5 --ignore-not-found
  kubectl delete pod,svc,deployment -l lab=1.5 --ignore-not-found

  warn "Để xóa ingress-nginx controller:"
  echo "  kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml"

  info "Done!"
}

# =============================================================================
case "$ACTION" in
  setup-ingress)    setup_ingress ;;
  view-nginx-conf)  view_nginx_conf ;;
  setup-gateway)    setup_gateway ;;
  teardown)         teardown ;;
  *)
    echo "Usage: $0 [setup-ingress|view-nginx-conf|setup-gateway|teardown]"
    exit 1
    ;;
esac
