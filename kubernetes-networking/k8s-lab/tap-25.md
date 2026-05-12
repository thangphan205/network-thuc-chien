---
marp: true
theme: default
paginate: true
style: |
  section { font-family: 'Segoe UI', sans-serif; font-size: 22px; background: #0d1021; color: #e2e8f0; }
  h1 { color: #a78bfa; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #34d399; font-size: 1.4em; border-bottom: 2px solid #34d399; padding-bottom: 0.2em; }
  h3 { color: #fbbf24; font-size: 1.1em; }
  code { background: #1a1a35; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1a1a35; border-left: 4px solid #a78bfa; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
  th { background: #2d1b69; color: #e9d5ff; padding: 10px 14px; font-weight: 600; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a2050; color: #e2e8f0; background: #151530; }
  tr:nth-child(even) td { background: #1e1e40; }
  blockquote { border-left: 4px solid #fbbf24; padding-left: 16px; color: #cbd5e1; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  pre .hljs-comment, pre .hljs-meta { color: #7dd3fc; }
  pre .hljs-keyword, pre .hljs-selector-tag { color: #f9a8d4; }
  pre .hljs-string, pre .hljs-attr { color: #86efac; }
  pre .hljs-number, pre .hljs-literal { color: #fde68a; }
  pre .hljs-variable, pre .hljs-template-variable { color: #c4b5fd; }
  pre .hljs-built_in, pre .hljs-name { color: #67e8f9; }
  pre .hljs-subst { color: #e2e8f0; }
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 25
## Lab 4: Cross-namespace AND/OR Bug — Prometheus không scrape được Backend

**Phần 2 — Calico Labs** · `#lab` `#cross-namespace` `#prometheus` `#AND` `#OR`

---

## Tình huống thực tế

```
Monitoring team báo:
"Prometheus trong namespace 'monitoring' không scrape được
 backend metrics endpoint (port 9090) trong namespace 'production'.
 Chúng tôi đã viết NetworkPolicy rồi nhưng vẫn timeout."

Thông tin:
- Namespace: monitoring (có label name=monitoring)  ← HOẶC CHƯA?
- Prometheus Pod label: role=prometheus
- Backend Pod label: app=backend
- Đã có policy cho phép nhưng không hoạt động
```

**Lab này: 2 bugs cùng lúc — phải fix cả 2 mới OK.**

---

## Lab Setup

```bash
multipass shell k8s-master

# Namespaces — monitoring KHÔNG có label (Bug 2)
kubectl create namespace monitoring 2>/dev/null || true
kubectl create namespace production 2>/dev/null || true
# Cố tình KHÔNG label namespace monitoring

# Verify
kubectl get namespace monitoring --show-labels
# NAME        LABELS   ← Không có label name=monitoring

# Deploy backend với metrics
kubectl apply -n production -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels: {app: backend}
spec:
  containers:
  - {name: app, image: nicolaka/netshoot, command: ["nc","-lk","-p","9090"]}
EOF

# Deploy Prometheus
kubectl apply -n monitoring -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: prometheus
  labels: {role: prometheus}
spec:
  containers:
  - {name: p, image: nicolaka/netshoot, command: ["sleep","infinity"]}
EOF

kubectl -n production wait --for=condition=Ready pod/backend --timeout=60s
kubectl -n monitoring wait --for=condition=Ready pod/prometheus --timeout=60s
```

---

## Apply Policy với 2 Bugs

```bash
BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')

# Default deny
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF

# Policy với BUG 1: OR thay vì AND (dấu - sai chỗ)
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-metrics
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring      # Bug 2: namespace chưa có label này!
    - podSelector:              # Bug 1: Dấu "-" → OR thay vì AND
        matchLabels:
          role: prometheus
    ports:
    - {protocol: TCP, port: 9090}
EOF

# Kiểm tra: Prometheus vẫn không vào được
kubectl -n monitoring exec prometheus -- nc -zv $BACKEND_IP 9090
# (timeout) ← Cả 2 bugs ngăn cản
```

---

## Debug Bug 1: OR vs AND

```bash
# Đọc kỹ lại policy
kubectl -n production get networkpolicy allow-prometheus-metrics -o yaml

# Phân tích YAML structure:
# from:
# - namespaceSelector: {name: monitoring}     ← Item 1 (OR)
# - podSelector: {role: prometheus}           ← Item 2 (OR) ← BUG!

# Với OR: bất kỳ Pod nào có role=prometheus BẤT KỲ NAMESPACE đều vào được!
# Và: bất kỳ Pod nào trong namespace monitoring đều vào được!
# Policy quá rộng VÀ không hoạt động đúng intent

# Nhưng tại sao VẪẪẪẪẪẪẪẪN timeout? → Bug 2!

# Deploy test pod với role=prometheus trong namespace default (không phải monitoring)
kubectl run test-prom --image=nicolaka/netshoot \
  --labels="role=prometheus" -- sleep infinity

TEST_IP=$(kubectl get pod test-prom -o jsonpath='{.status.podIP}')
kubectl exec test-prom -- nc -zv $BACKEND_IP 9090
# (timeout) ← Hmm, vẫn timeout? → Bug 2 blocking
```

---

## Debug Bug 2: Namespace thiếu label

```bash
# Kiểm tra namespace labels
kubectl get namespace monitoring --show-labels
# NAME        LABELS
# monitoring  <none>   ← BUG 2! Không có label name=monitoring

# Policy yêu cầu:
# namespaceSelector: matchLabels: {name: monitoring}
# → Tìm namespace có label name=monitoring
# → Không namespace nào match → rule này không có tác dụng

# Policy đang thực sự hoạt động như:
# from:
# - (empty namespaceSelector = match nothing)  ← Bug 2 làm cho Item 1 = nothing
# - podSelector: {role: prometheus}             ← Chỉ Item 2 có tác dụng
# Nhưng với mọi pod có role=prometheus trong BẤT KỲ namespace
```

---

## Fix cả 2 Bugs

```bash
# Fix Bug 2: Label namespace monitoring
kubectl label namespace monitoring name=monitoring

# Fix Bug 1: Đổi policy thành AND (xóa dấu - thừa)
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-metrics
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring   # Namespace phải là monitoring
      podSelector:           # ← Không có dấu "-" = AND!
        matchLabels:
          role: prometheus   # VÀ Pod phải là prometheus
    ports:
    - {protocol: TCP, port: 9090}
EOF

# Test: Bây giờ phải hoạt động
kubectl -n monitoring exec prometheus -- nc -zv $BACKEND_IP 9090
# Connection to 10.244.X.Y 9090 port succeeded! ✅

# Verify test-prom (wrong namespace) bị chặn
kubectl exec test-prom -- nc -zv $BACKEND_IP 9090
# (timeout) ✅ Đúng! test-prom không trong monitoring namespace
```

---

## Key Lessons

**2 bugs pattern — phải fix cùng lúc:**
```
Bug 1 (OR logic): Dấu "-" thừa → policy quá rộng (security hole)
Bug 2 (missing label): namespaceSelector không match → policy không hoạt động

Cả 2 tồn tại cùng lúc → debug khó vì:
- Bug 2 mask Bug 1 (policy không hoạt động nên không thấy security hole)
- Fix chỉ Bug 2 → Bug 1 trở thành security hole thực sự!
```

**Checklist trước khi apply cross-namespace policy:**
```bash
# 1. Verify namespace labels
kubectl get namespace <ns> --show-labels

# 2. Đếm dấu "-" trong from block (AND vs OR)

# 3. Test với rogue pod từ namespace khác
kubectl run rogue -n <other-ns> --image=nicolaka/netshoot -- sleep infinity
kubectl exec rogue -- nc -zv <backend-ip> <port>
# Expected: timeout (blocked)
```

> **Tập tiếp theo:** Calico Observability — Prometheus + Grafana + AlertManager stack miễn phí.
