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
  section.warn { background: linear-gradient(135deg, #1a0800 0%, #0d1021 100%); }
  section.warn h2 { color: #f87171; border-bottom-color: #f87171; }
---

<!-- _class: ep -->

# Tập 10
## Giới hạn của Flannel: Tại sao không có NetworkPolicy?

**Phần 1 — Flannel** · `#flannel` `#security` `#NetworkPolicy` `#lateral-movement`

---

## Mục tiêu tập này

- Demo lateral movement trong cluster dùng Flannel
- Giải thích tại sao Flannel không implement NetworkPolicy
- Đo blast radius khi 1 Pod bị compromise
- So sánh risk level giữa cluster có/không có NetworkPolicy

**Prerequisites:** Cluster từ Tập 6-9 với Flannel đang chạy

---

<!-- _class: warn -->

## Flannel: Security hole by design

```
Cluster Flannel — mọi Pod đều "thấy" nhau:

frontend (10.244.1.5)  ──────────────────────────────►  database (10.244.2.10)
hacker-pod (10.244.1.9)  ──────────────────────────►  database (10.244.2.10)
hacker-pod (10.244.1.9)  ──────────────────────────►  payment-api (10.244.3.5)
hacker-pod (10.244.1.9)  ──────────────────────────►  redis (10.244.2.20)
hacker-pod (10.244.1.9)  ──────────────────────────►  internal-api (10.244.3.8)

Không có gì ngăn cản!
```

**Tại sao Flannel không có NetworkPolicy?**
- Flannel là CNI "minimal" — chỉ giải quyết connectivity
- NetworkPolicy cần kernel hooks (iptables/eBPF) tại mỗi Node
- Flannel không install hooks đó → không enforce được
- Nếu apply NetworkPolicy resource → **K8s chấp nhận** nhưng **không có tác dụng gì**!

---

## Nguy hiểm thầm lặng: NetworkPolicy bị bỏ qua

```bash
# Người dùng nghĩ rằng NetworkPolicy đang hoạt động...
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF

kubectl get networkpolicy
# NAME       POD-SELECTOR   AGE
# deny-all   <none> (All)   5s  ← K8s chấp nhận!

# ...nhưng thực ra không có tác dụng gì!
kubectl exec hacker-pod -- curl http://database:5432
# ← Vẫn kết nối được! NetworkPolicy bị Flannel bỏ qua hoàn toàn
```

> **Đây là bug nguy hiểm nhất:** người dùng tưởng mình đang được bảo vệ nhưng thực ra không.

---

<!-- _class: lab -->

## Lab: Demo Lateral Movement với Flannel

```bash
multipass shell k8s-master

# Setup môi trường: deploy fake "database" và "payment API"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: database
  labels:
    app: database
spec:
  nodeName: k8s-worker2
  containers:
  - name: db
    image: nicolaka/netshoot
    command: ["nc", "-lk", "-p", "5432"]
---
apiVersion: v1
kind: Pod
metadata:
  name: payment-api
  labels:
    app: payment
spec:
  nodeName: k8s-worker2
  containers:
  - name: api
    image: nginx
    ports:
    - containerPort: 80
EOF

kubectl wait --for=condition=Ready pod/database pod/payment-api --timeout=60s
```

---

## Lab: Simulate attacker từ compromised Pod

```bash
DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')
PAYMENT_IP=$(kubectl get pod payment-api -o jsonpath='{.status.podIP}')

# Simulate: hacker chiếm được frontend Pod
# Từ trong "frontend" Pod, scan tất cả targets
kubectl exec pod-a -- bash -c "
  echo '=== Scanning from compromised pod ==='
  
  # Tìm tất cả Pods trong cluster
  echo 'Database IP: $DB_IP'
  nc -zv $DB_IP 5432
  echo 'Database port 5432: OPEN!'
  
  # Scan payment API
  echo 'Payment API: $PAYMENT_IP'
  curl -s http://$PAYMENT_IP | head -3
  echo 'Payment API port 80: ACCESSIBLE!'
  
  # Scan DNS để tìm thêm services
  nslookup kubernetes.default.svc.cluster.local
  echo 'K8s API server: FOUND!'
"
```

---

## Lab: Apply NetworkPolicy — và chứng minh nó vô dụng với Flannel

```bash
# Áp dụng NetworkPolicy "deny all"
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-everything
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# MONG ĐỢI: Hacker pod không còn kết nối được
# THỰC TẾ với Flannel:
kubectl exec pod-a -- nc -zv $DB_IP 5432
# Connection to 10.244.2.10 5432 port [tcp/postgresql] succeeded!
# ← NetworkPolicy hoàn toàn không có tác dụng!

# Verify: Flannel không install bất kỳ iptables rule nào cho NetworkPolicy
multipass exec k8s-worker1 -- sudo iptables -L | grep -i "network\|policy\|deny"
# (không có output) ← Không có rules nào!
```

---

## Blast Radius so sánh

| Scenario | Blast Radius khi 1 Pod bị chiếm |
| :--- | :--- |
| **Flannel (không policy)** | **Toàn bộ cluster** — mọi service, mọi database |
| **Calico + Default Deny** | Chỉ service Pod đó có quyền gọi |
| **Cilium + L7 Policy** | Chỉ HTTP endpoints cụ thể Pod đó có quyền gọi |

```
Flannel cluster với 50 microservices:
1 Pod bị compromise → hacker có thể scan/tấn công 49 services còn lại

Calico cluster với Default Deny:
1 Pod bị compromise → hacker chỉ reach được 2-3 services
(chỉ những service policy cho phép)
```

---

## Key Takeaways

**Flannel phù hợp:**
```
✅ Dev/local lab
✅ Learning/teaching (đơn giản nhất)
✅ Cluster không expose ra internet
✅ Thử nghiệm tính năng K8s (không phải security)
```

**Flannel KHÔNG phù hợp:**
```
❌ Production với multiple teams
❌ Cluster chứa sensitive data (database, payment)
❌ Compliance requirements (PCI-DSS, HIPAA, SOC2)
❌ Multi-tenant cluster
```

**Quyết định tiếp theo:** Thay Flannel bằng Calico để có NetworkPolicy.

> **Phần tiếp theo (Tập 11):** Tại sao cần Calico? Lateral movement & Blast radius — bài toán Flannel không giải được.
