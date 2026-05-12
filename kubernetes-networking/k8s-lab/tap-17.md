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

# Tập 17
## Union Logic: NetworkPolicy hoạt động như Security Group, không phải ACL

**Phần 2 — Calico** · `#NetworkPolicy` `#union-logic` `#allow-list` `#SecurityGroup`

---

## Mục tiêu tập này

- Chứng minh nhiều NetworkPolicy cùng select 1 Pod = cộng hưởng (additive)
- Phân biệt NetworkPolicy (allowlist) vs ACL (có DENY tường minh)
- Demo không có cách "deny" cụ thể bằng NetworkPolicy chuẩn
- Giới thiệu AdminNetworkPolicy cho DENY tường minh

**Prerequisites:** Cluster Calico từ Tập 15-16

---

## Security Group vs ACL

**AWS Security Group (allow-only):**
```
SG-1: Allow port 80 from 10.0.1.0/24
SG-2: Allow port 443 from 0.0.0.0/0
SG-3: Allow port 22 from 10.0.0.5/32

Kết quả: Port 80, 443, 22 OPEN
         Không có "deny" nào xung đột
         SG-1 không "ghi đè" SG-2
```

**AWS NACL (allow + deny):**
```
Rule 100: Allow port 80
Rule 200: Deny port 80 from 1.2.3.4
Rule 300: Allow all

NACL có thứ tự, rule thấp hơn thắng
DENY ghi đè ALLOW
```

**K8s NetworkPolicy = Security Group (not NACL)**

---

## Union Logic trong K8s NetworkPolicy

```yaml
# Policy A: Frontend → Backend port 8080
# Policy B: Monitoring → Backend port 9090
# Policy C: DB callback → Backend port 8080

# Kết quả cho Backend Pod (union của tất cả ingress rules):
# Allow: from frontend: port 8080
# Allow: from monitoring: port 9090
# Allow: from db-pod: port 8080

# KHÔNG có policy nào cancel policy kia!
# Không có "priority" hay "order"
# Tất cả đều ADDITIVE
```

**Hệ quả quan trọng:**
```
Bạn KHÔNG thể viết "deny port 80 from specific IP" 
bằng K8s NetworkPolicy chuẩn.

Cách duy nhất để deny: KHÔNG CÓ rule allow cho traffic đó.
```

---

<!-- _class: lab -->

## Lab: Demo Union Logic

```bash
multipass shell k8s-master

# Setup: Backend với default deny
kubectl -n production delete networkpolicy --all 2>/dev/null
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF

# Tạo thêm pods để test
kubectl run frontend2 -n production --image=nicolaka/netshoot \
  --labels="app=frontend2" -- sleep infinity
kubectl run db-pod -n production --image=nicolaka/netshoot \
  --labels="app=database" -- sleep infinity
kubectl wait -n production --for=condition=Ready pod/frontend2 pod/db-pod --timeout=60s

BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
```

---

## Lab: Add policies one by one, verify union

```bash
# Không có policy → tất cả bị deny
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080  # ❌
kubectl -n production exec frontend2 -- nc -zv $BACKEND_IP 8080  # ❌

# Apply Policy A: Allow frontend → backend:8080
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
EOF

kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080    # ✅ Policy A
kubectl -n production exec frontend2 -- nc -zv $BACKEND_IP 8080   # ❌ Không có rule cho frontend2

# Apply Policy B: Allow frontend2 → backend:8080
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend2
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend2
    ports:
    - protocol: TCP
      port: 8080
EOF

# Bây giờ CẢ HAI đều được vào!
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080    # ✅ Policy A vẫn đúng
kubectl -n production exec frontend2 -- nc -zv $BACKEND_IP 8080   # ✅ Policy B thêm vào
# Policy A KHÔNG bị Policy B ghi đè!
```

---

## Lab: Không thể DENY tường minh

```bash
# Scenario: Bạn muốn deny frontend2 nhưng vẫn allow frontend
# Cách sai: Xóa allow-frontend2
kubectl delete -n production networkpolicy allow-frontend2
# Kết quả: frontend2 bị deny ✅ (không còn rule) — OK theo cách này

# Nhưng không thể viết "Deny frontend2 explicitly" bằng NetworkPolicy chuẩn!
# Đây là giới hạn của NetworkPolicy

# Giải pháp: AdminNetworkPolicy (API mới, K8s 1.29+)
# Hoặc: Calico GlobalNetworkPolicy với action: Deny
kubectl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-frontend2-explicit
spec:
  selector: app == 'backend'
  order: 100
  ingress:
  - action: Deny
    source:
      selector: app == 'frontend2'
EOF
# Calico mở rộng cho phép DENY tường minh!
```

---

## Key Takeaways

**NetworkPolicy Union Logic:**
```
Policy 1 + Policy 2 + Policy 3 = Union của tất cả allows
Không có cancel, không có priority, không có conflict
```

**Muốn DENY tường minh → cần:**
```
Option 1: Calico GlobalNetworkPolicy / NetworkPolicy với action: Deny
Option 2: AdminNetworkPolicy (K8s 1.29+, cluster-scope)
Option 3: Cilium CiliumNetworkPolicy với deny rules
```

**Quy tắc nhớ:**
```
K8s NetworkPolicy = Allowlist thuần túy
                  = "Ai được vào" chứ không phải "ai bị cấm"
                  = Giống Security Group, không phải firewall ACL
```

> **Tập tiếp theo:** BGP trong Calico — cluster là một Autonomous System, peer với ToR switch datacenter.
