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

# Tập 15
## NetworkPolicy cơ bản: Default Deny và Ingress Policy

**Phần 2 — Calico** · `#NetworkPolicy` `#default-deny` `#ingress` `#least-privilege`

---

## Mục tiêu tập này

- Viết `default-deny` policy cho toàn namespace
- Viết ingress policy cho phép traffic cụ thể
- Test từng bước: trước policy, sau deny, sau allow
- Hiểu tại sao phải allow DNS traffic riêng

**Prerequisites:** Cluster Calico từ Tập 11, không có NetworkPolicy nào đang active

---

## Bước 1: Default Allow (không có policy)

```
Khi không có NetworkPolicy nào trong namespace:
→ K8s cho phép TẤT CẢ traffic (default allow)

frontend → backend    ✅
attacker → backend    ✅ (không ai chặn)
```

**Nguyên tắc K8s NetworkPolicy:**
> "Chỉ khi có ít nhất 1 NetworkPolicy SELECT một Pod,
>  thì traffic đến/đi Pod đó mới bị restrict.
>  Pod không bị select bởi policy nào = không bị restrict gì."

---

## Bước 2: Default Deny Ingress

```yaml
# Chặn TẤT CẢ ingress vào namespace production
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}       # {} = select ALL pods trong namespace
  policyTypes:
  - Ingress             # Không có ingress rules = deny ALL ingress
  # Không liệt kê Egress = egress vẫn được phép
```

**Kết quả:**
```
frontend → backend    ❌ (ingress đến backend bị deny)
backend → database    ✅ (egress từ backend vẫn OK)
external → frontend   ❌ (ingress đến frontend bị deny)
```

---

## Bước 3: Allow cụ thể

```yaml
# Allow frontend gọi backend port 8080
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend            # Policy này áp dụng cho Pod backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend       # Chỉ cho phép từ Pod frontend
    ports:
    - protocol: TCP
      port: 8080              # Chỉ port 8080
```

---

## Lỗi phổ biến #1: Quên allow DNS!

```bash
# Sau khi apply default-deny-egress:
kubectl exec backend -- curl http://service-name
# curl: (6) Could not resolve host: service-name

# Tại sao? DNS query đến CoreDNS cũng bị chặn!

# Fix: Phải có rule allow DNS
```

```yaml
# Allow egress DNS (QUAN TRỌNG — không có DNS = không làm gì được)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

---

<!-- _class: lab -->

## Lab: Tạo namespace và Deploy

```bash
multipass shell k8s-master

# Tạo namespace production
kubectl create namespace production

# Deploy frontend và backend
kubectl apply -n production -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels: {app: frontend, tier: web}
spec:
  containers:
  - name: web
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels: {app: backend, tier: api}
spec:
  containers:
  - name: api
    image: nicolaka/netshoot
    command: ["nc", "-lk", "-p", "8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
spec:
  selector: {app: backend}
  ports: [{port: 8080, targetPort: 8080}]
EOF

kubectl -n production wait --for=condition=Ready pod/frontend pod/backend --timeout=60s
```

---

## Lab: Test từng bước

```bash
# Bước 1: Không có policy → tất cả pass
kubectl -n production exec frontend -- nc -zv backend-svc 8080
# Connection to backend-svc 8080 port succeeded! ✅

# Bước 2: Apply default deny ingress
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF

kubectl -n production exec frontend -- nc -zv backend-svc 8080
# (timeout) ← Backend ingress bị deny ✅

# Bước 3: Apply allow rule
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

kubectl -n production exec frontend -- nc -zv backend-svc 8080
# Connection to backend-svc 8080 succeeded! ✅ (rule được apply ngay)
```

---

## Lab: Verify DNS vẫn hoạt động

```bash
# Kiểm tra DNS từ trong Pod (egress chưa bị deny)
kubectl -n production exec frontend -- nslookup backend-svc
# Server: 10.96.0.10
# Name: backend-svc.production.svc.cluster.local
# Address: 10.96.X.Y ✅

# Apply default deny egress để thấy DNS bị break
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
spec:
  podSelector: {}
  policyTypes: [Egress]
EOF

# DNS bị break!
kubectl -n production exec frontend -- nslookup backend-svc
# ;; connection timed out; no servers could be reached ❌

# Fix: Apply DNS allow rule
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF

kubectl -n production exec frontend -- nslookup backend-svc
# Resolved! ✅ DNS hoạt động trở lại
```

---

## Key Takeaways

**Thứ tự triển khai policy đúng:**
```
1. Allow DNS egress (LUÔN LÀM ĐẦU TIÊN!)
2. Allow egress cần thiết (HTTP, database...)
3. Apply default deny ingress
4. Allow ingress cụ thể
5. Apply default deny egress
```

**Test matrix sau mỗi policy:**
```bash
# Script test nhanh
for src in frontend backend; do
  for dst_port in "backend-svc 8080" "database 5432"; do
    result=$(kubectl -n production exec $src -- nc -zv $dst_port 2>&1)
    echo "$src → $dst_port: $result"
  done
done
```

> **Tập tiếp theo:** Cross-namespace Policy — AND vs OR, sai 1 dấu gạch là sai policy!
