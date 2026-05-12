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

# Tập 16
## Cross-namespace Policy: AND vs OR — Dấu gạch "-" quan trọng thế nào!

**Phần 2 — Calico** · `#NetworkPolicy` `#cross-namespace` `#AND` `#OR` `#YAML`

---

## Mục tiêu tập này

- Phân biệt rõ AND vs OR logic trong NetworkPolicy YAML
- Demo sự khác biệt bằng cách kiểm tra traffic thực tế
- Viết cross-namespace policy đúng cho Prometheus scraping
- Hiểu tại sao namespace phải có label

**Prerequisites:** Cluster Calico, namespace `production` và `monitoring` có Pods

---

## Bài toán: Prometheus scrape backend metrics

```
Namespace: monitoring
  Pod: prometheus (label: role=prometheus)

Namespace: production
  Pod: backend (label: app=backend)
  Port: 9090 (metrics endpoint)

Goal: Chỉ cho phép prometheus trong namespace monitoring
      scrape backend metrics (port 9090)
      KHÔNG cho phép prometheus nào khác scrape
```

**Yêu cầu:** Cả 2 điều kiện phải đúng đồng thời:
1. Phải là Pod có label `role: prometheus`
2. Phải ở trong namespace `monitoring`

---

## OR logic (Bug thường gặp)

```yaml
ingress:
- from:
  - namespaceSelector:          # Điều kiện A
      matchLabels:
        name: monitoring
  - podSelector:                # ← Có dấu "-" → ITEM MỚI → OR
      matchLabels:
        role: prometheus
```

**Kết quả thực tế (WRONG):**
```
Prometheus (monitoring namespace)      → ✅ (match điều kiện A)
Prometheus (other namespace)           → ✅ (match điều kiện B — role=prometheus bất kỳ đâu!)
Bất kỳ Pod nào trong monitoring       → ✅ (match điều kiện A — bất kỳ Pod nào trong monitoring!)
Rogue pod (monitoring, không phải prom) → ✅ (match điều kiện A!)
```

**Policy quá rộng — không an toàn!**

---

## AND logic (Đúng)

```yaml
ingress:
- from:
  - namespaceSelector:          # Điều kiện A
      matchLabels:
        name: monitoring
    podSelector:                # ← KHÔNG có dấu "-" → CÙNG ITEM → AND
      matchLabels:
        role: prometheus
```

**Kết quả (CORRECT):**
```
Prometheus (monitoring namespace, role=prometheus)  → ✅ (A AND B)
Prometheus (other namespace, role=prometheus)       → ❌ (B đúng nhưng A sai)
Random pod (monitoring namespace, no role)          → ❌ (A đúng nhưng B sai)
```

---

## Quy tắc YAML nhớ mãi

```yaml
# OR: mỗi điều kiện là một list item (có dấu -)
from:
- namespaceSelector: ...   # Item 1
- podSelector: ...         # Item 2 (OR với Item 1)

# AND: cùng một list item
from:
- namespaceSelector: ...   # Cùng item
  podSelector: ...         # AND với namespaceSelector trên
```

**Visual:**
```
OR  → nhiều dấu "-" → nhiều items → any ONE must match
AND → một dấu "-"  → một item    → ALL must match within item
```

---

<!-- _class: lab -->

## Lab: Deploy môi trường test

```bash
multipass shell k8s-master

# Tạo namespaces
kubectl create namespace production 2>/dev/null || true
kubectl create namespace monitoring 2>/dev/null || true

# Label namespaces (BẮT BUỘC cho namespaceSelector)
kubectl label namespace monitoring name=monitoring
kubectl label namespace production name=production

# Deploy backend với metrics endpoint
kubectl apply -n production -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels: {app: backend}
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["nc", "-lk", "-p", "9090"]
EOF

# Deploy prometheus trong monitoring
kubectl apply -n monitoring -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: prometheus
  labels: {role: prometheus}
spec:
  containers:
  - name: prom
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

# Deploy rogue pod trong monitoring (không có role=prometheus)
kubectl run rogue -n monitoring --image=nicolaka/netshoot -- sleep infinity

kubectl -n production wait --for=condition=Ready pod/backend --timeout=60s
kubectl -n monitoring wait --for=condition=Ready pod/prometheus pod/rogue --timeout=60s
```

---

## Lab: Apply policy OR (buggy) và test

```bash
BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')

# Apply default deny cho production
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF

# Apply policy OR (buggy version)
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-OR-bug
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    - podSelector:              # ← Bug: dấu "-" → OR
        matchLabels:
          role: prometheus
    ports:
    - protocol: TCP
      port: 9090
EOF

# Test: Rogue pod PHẢI bị chặn nhưng...
kubectl -n monitoring exec rogue -- nc -zv $BACKEND_IP 9090
# Connection succeeded! ← Bug! Rogue pod vào được vì match namespace monitoring
```

---

## Lab: Fix thành AND và verify

```bash
# Xóa policy buggy
kubectl delete -n production networkpolicy allow-prometheus-OR-bug

# Apply policy AND (correct)
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-AND-correct
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
      podSelector:              # ← Đúng: không có dấu "-" → AND
        matchLabels:
          role: prometheus
    ports:
    - protocol: TCP
      port: 9090
EOF

# Test lại:
kubectl -n monitoring exec prometheus -- nc -zv $BACKEND_IP 9090
# Connection succeeded! ✅ Prometheus OK

kubectl -n monitoring exec rogue -- nc -zv $BACKEND_IP 9090
# Timeout ✅ Rogue bị chặn!
```

---

## Key Takeaways

**Nhớ bằng cách đếm dấu gạch:**
```yaml
from:
- namespaceSelector: {}    # Dấu "-" này = item mới
  podSelector: {}          # CÙNG item → AND

from:
- namespaceSelector: {}    # Dấu "-" này = item 1
- podSelector: {}          # Dấu "-" này = item 2 → OR
```

**Namespace phải có label:**
```bash
kubectl label namespace monitoring name=monitoring
# Nếu không label → namespaceSelector không match được!
```

**Kiểm tra nhanh:**
```bash
kubectl get namespace monitoring --show-labels
# NAME        LABELS
# monitoring  name=monitoring   ← OK
```

> **Tập tiếp theo:** Union Logic — nhiều NetworkPolicy cùng chọn 1 Pod thì cộng hưởng như thế nào?
