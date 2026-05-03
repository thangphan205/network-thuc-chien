#!/usr/bin/env bash
# =============================================================================
# Lab 1.6: Bảo mật với NetworkPolicy
# Chạy: bash lab-config.sh [setup|apply-deny|fix-dns|test-policy|teardown]
# =============================================================================
set -euo pipefail

ACTION="${1:-setup}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

# =============================================================================
setup() {
  info "=== Lab 1.6: Tạo môi trường multi-tier application ==="

  # Tạo các namespaces
  kubectl create namespace frontend --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace backend  --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace frontend name=frontend --overwrite
  kubectl label namespace backend  name=backend  --overwrite
  kubectl label namespace database name=database --overwrite

  kubectl apply -f - <<'EOF'
---
# === Frontend Tier ===
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: frontend
  labels:
    lab: "1.6"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
      tier: web
  template:
    metadata:
      labels:
        app: frontend
        tier: web
    spec:
      containers:
      - name: web
        image: nicolaka/netshoot
        command: ["sleep", "infinity"]
---
# === Backend API Tier ===
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: backend
  labels:
    lab: "1.6"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
      tier: api
  template:
    metadata:
      labels:
        app: api
        tier: api
    spec:
      containers:
      - name: api
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: backend
  labels:
    lab: "1.6"
spec:
  selector:
    app: api
  ports:
  - port: 80
---
# === Database Tier ===
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: database
  labels:
    lab: "1.6"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
      tier: database
  template:
    metadata:
      labels:
        app: db
        tier: database
    spec:
      containers:
      - name: db
        image: nginx:alpine    # Dùng nginx để giả lập db port
        ports:
        - containerPort: 5432
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: database
  labels:
    lab: "1.6"
spec:
  selector:
    app: db
  ports:
  - name: pg
    port: 5432
    targetPort: 80   # redirect về 80 vì dùng nginx
EOF

  kubectl wait --for=condition=Ready pod -l lab=1.6 -n frontend --timeout=120s
  kubectl wait --for=condition=Ready pod -l lab=1.6 -n backend  --timeout=120s
  kubectl wait --for=condition=Ready pod -l lab=1.6 -n database --timeout=120s

  DB_SVC="db.database.svc.cluster.local"
  API_SVC="api.backend.svc.cluster.local"
  FRONTEND_POD=$(kubectl get pod -n frontend -l app=frontend -o jsonpath='{.items[0].metadata.name}')

  echo ""
  info "=== Môi trường sẵn sàng. Trước khi apply NetworkPolicy ==="
  echo ""
  step "Test: Frontend → API (phải thành công)"
  echo "  kubectl exec -n frontend ${FRONTEND_POD} -- curl -s --max-time 3 ${API_SVC}"
  echo ""
  step "Test: Frontend → Database (phải thành công - trước khi có policy)"
  echo "  kubectl exec -n frontend ${FRONTEND_POD} -- curl -s --max-time 3 ${DB_SVC}"
  echo ""
  warn "Tiếp theo: chạy './lab-config.sh apply-deny' để áp dụng NetworkPolicy"
}

# =============================================================================
apply_deny() {
  info "=== Áp dụng NetworkPolicy: Default-deny + Intentional DNS break ==="
  warn "Chú ý: Policy này sẽ CỐ TÌNH phá DNS để bạn thấy lỗi kinh điển!"

  kubectl apply -f - <<'EOF'
# DEFAULT DENY cho database namespace
# Policy này THIẾU DNS rule - cố tình để học viên thấy lỗi!
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-from-backend-BROKEN
  namespace: database
  labels:
    lab: "1.6"
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: backend
      podSelector:
        matchLabels:
          tier: api
    ports:
    - port: 5432
  # ← Egress bị deny ALL (không có rule)
  # ← Không có rule cho DNS (port 53) → DNS bị chặn!
EOF

  echo ""
  info "=== Policy áp dụng xong. Test DNS bị vỡ ==="
  DB_POD=$(kubectl get pod -n database -l app=db -o jsonpath='{.items[0].metadata.name}')
  echo ""
  step "Chạy lệnh sau để thấy DNS bị chặn:"
  echo "  kubectl exec -n database ${DB_POD} -- nslookup kubernetes.default"
  echo "  # Kết quả mong đợi: connection timed out  ← Đây là lỗi!"
  echo ""
  warn "→ Tiếp theo: chạy './lab-config.sh fix-dns' để sửa policy"
}

# =============================================================================
fix_dns() {
  info "=== Sửa NetworkPolicy: Thêm DNS egress rule ==="

  kubectl apply -f - <<'EOF'
# Policy đúng: Có đầy đủ DNS rule trong Egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-from-backend-FIXED
  namespace: database
  labels:
    lab: "1.6"
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: backend
      podSelector:
        matchLabels:
          tier: api
    ports:
    - port: 5432
  egress:
  # ← QUAN TRỌNG: LUÔN PHẢI CÓ RULE NÀY!
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
EOF

  # Xóa policy bị lỗi
  kubectl delete networkpolicy db-allow-from-backend-BROKEN -n database --ignore-not-found

  DB_POD=$(kubectl get pod -n database -l app=db -o jsonpath='{.items[0].metadata.name}')
  echo ""
  info "=== Policy đã sửa. Test lại DNS ==="
  step "DNS phải hoạt động trở lại:"
  echo "  kubectl exec -n database ${DB_POD} -- nslookup kubernetes.default"
}

# =============================================================================
test_policy() {
  info "=== Test toàn bộ Policy sau khi fix ==="

  FRONTEND_POD=$(kubectl get pod -n frontend -l app=frontend -o jsonpath='{.items[0].metadata.name}')
  BACKEND_POD=$(kubectl get pod -n backend -l app=api -o jsonpath='{.items[0].metadata.name}')
  DB_SVC="db.database.svc.cluster.local"

  echo ""
  step "Test 1: Frontend → Database (phải BỊ CHẶN)"
  kubectl exec -n frontend "${FRONTEND_POD}" -- curl -s --max-time 3 "${DB_SVC}:5432" \
    && echo -e "${RED}❌ PASS (không mong muốn)${NC}" \
    || echo -e "${GREEN}✅ BLOCKED (đúng như policy)${NC}"

  echo ""
  step "Test 2: Backend → Database (phải ĐƯỢC PHÉP)"
  kubectl exec -n backend "${BACKEND_POD}" -- curl -s --max-time 3 "${DB_SVC}" \
    && echo -e "${GREEN}✅ ALLOWED (đúng như policy)${NC}" \
    || echo -e "${RED}❌ BLOCKED (không mong muốn)${NC}"
}

# =============================================================================
teardown() {
  info "Dọn dẹp Lab 1.6..."
  kubectl delete networkpolicy -l lab=1.6 -n database --ignore-not-found
  kubectl delete pod,svc,deployment -l lab=1.6 -n frontend --ignore-not-found
  kubectl delete pod,svc,deployment -l lab=1.6 -n backend  --ignore-not-found
  kubectl delete pod,svc,deployment -l lab=1.6 -n database --ignore-not-found
  kubectl delete namespace frontend backend database --ignore-not-found
  info "Done!"
}

# =============================================================================
case "$ACTION" in
  setup)       setup ;;
  apply-deny)  apply_deny ;;
  fix-dns)     fix_dns ;;
  test-policy) test_policy ;;
  teardown)    teardown ;;
  *)
    echo "Usage: $0 [setup|apply-deny|fix-dns|test-policy|teardown]"
    exit 1
    ;;
esac
