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

# Tập 21
## Troubleshooting Calico: calicoctl → ip route → iptables-save

**Phần 2 — Calico** · `#troubleshooting` `#debug` `#methodology` `#calicoctl`

---

## Mục tiêu tập này

- Học workflow debug Calico có hệ thống (không đoán mò)
- Dùng đủ bộ tool: calicoctl, ip route, iptables-save, tcpdump
- Debug 3 scenario khác nhau trong lab
- Biết lúc nào check control plane vs data plane

**Prerequisites:** Cluster Calico đang chạy, có network policies

---

## Workflow debug Calico — 5 bước

```
Symptom: Pod A không connect được Pod B

Bước 1: CHECK BASICS
─────────────────────────────────────────────
  kubectl get pods -o wide     # Pod đang chạy? Đúng node?
  kubectl get endpoints        # Service có endpoints chưa?

Bước 2: CHECK BGP (nếu dùng BGP mode)
─────────────────────────────────────────────
  calicoctl node status        # BGP sessions UP?
  ip route show                # Có route đến subnet của Pod B?

Bước 3: CHECK IPTABLES POLICY
─────────────────────────────────────────────
  iptables-save | grep cali    # Calico rules có được tạo chưa?
  iptables -L cali-FORWARD -n  # Chain đang làm gì?

Bước 4: TRACE PACKET
─────────────────────────────────────────────
  tcpdump -i any host <pod-ip> # Packet có đến nơi không?

Bước 5: CHECK FELIX LOGS
─────────────────────────────────────────────
  kubectl logs -n calico-system calico-node  # Felix error?
```

---

<!-- _class: lab -->

## Lab: Setup 3 broken scenarios

```bash
multipass shell k8s-master

# Deploy test services
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels: {app: client}
spec:
  containers:
  - {name: c, image: nicolaka/netshoot, command: ["sleep","infinity"]}
---
apiVersion: v1
kind: Pod
metadata:
  name: server
  labels: {app: server}
spec:
  containers:
  - {name: s, image: nicolaka/netshoot, command: ["nc","-lk","-p","8080"]}
---
apiVersion: v1
kind: Service
metadata:
  name: server-svc
spec:
  selector: {app: server}
  ports: [{port: 8080, targetPort: 8080}]
EOF

kubectl wait --for=condition=Ready pod/client pod/server --timeout=60s
SERVER_IP=$(kubectl get pod server -o jsonpath='{.status.podIP}')
```

---

## Lab Scenario 1: Policy deny không rõ lý do

```bash
# Setup broken: Apply deny policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: debug-deny
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes: [Ingress]
  ingress: []  # Không có ingress rules = deny all
EOF

# Symptom
kubectl exec client -- nc -zv $SERVER_IP 8080   # Timeout

# Debug workflow:
# Bước 1: Pod đang chạy bình thường
kubectl get pods -o wide

# Bước 2: Xem policy đang apply
kubectl get networkpolicy
# NAME        POD-SELECTOR   AGE
# debug-deny  app=server     30s

# Bước 3: Xem iptables chain của server pod
SERVER_NS=$(kubectl get pod server -o jsonpath='{.metadata.namespace}')
calicoctl get workloadendpoint | grep server
# → Thấy endpoint ID

# Bước 4: Check iptables rule cho endpoint đó
sudo iptables -L cali-tw-<endpoint-id> -n
# → Thấy không có ACCEPT rule nào → DROP

# Fix:
kubectl delete networkpolicy debug-deny
```

---

## Lab Scenario 2: Route bị thiếu (BGP mode)

```bash
# Simulate BGP route missing (restart BIRD)
kubectl -n calico-system rollout restart daemonset calico-node

# Trong thời gian ngắn sau restart:
kubectl exec client -- ping -c 3 $SERVER_IP
# Request timeout (route bị xóa rồi chưa được học lại)

# Debug:
# Bước 1: Check BGP session
calicoctl node status
# STATE: OpenSent (đang reconnect) → chờ ESTABLISHED

# Bước 2: Check routing table
ip route show | grep 10.244
# (Route bị xóa) → Route sẽ tự recover sau vài giây

# Bước 3: Watch recovery
watch -n1 'calicoctl node status; ip route show | grep 10.244'

# Sau 10-30 giây: STATE = up, routes trở lại
kubectl exec client -- ping -c 3 $SERVER_IP   # OK ✅
```

---

## Lab Scenario 3: Label typo

```bash
# Setup: Policy nhưng Pod có label sai
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client        # Policy expect "client"
    ports:
    - protocol: TCP
      port: 8080
EOF

# Đổi label của client Pod thành "cliennt" (typo)
kubectl label pod client app=cliennt --overwrite

# Symptom: timeout
kubectl exec client -- nc -zv $SERVER_IP 8080

# Debug:
kubectl get pod client --show-labels
# LABELS: app=cliennt  ← Typo!

kubectl get networkpolicy allow-client -o yaml | grep -A5 "from:"
# matchLabels: {app: client}  ← Policy expect "client"

# Fix:
kubectl label pod client app=client --overwrite
kubectl exec client -- nc -zv $SERVER_IP 8080  # OK ✅
```

---

## Key Takeaways

**Debug command toolkit:**
```bash
# Control plane
calicoctl node status          # BGP sessions
calicoctl get workloadendpoint # Pod endpoints Felix knows about
calicoctl get networkpolicy    # Policies đang active

# Data plane
ip route show                  # Routing table
iptables-save | grep cali      # All Calico rules
iptables -L cali-FORWARD -nv   # Forward chain stats (packet count!)
conntrack -L | grep <ip>       # Connection state

# Packet tracing
tcpdump -i any host <ip> -n    # Packet capture
tcpdump -i any host <ip> -n port 8080  # Specific port

# Logs
kubectl logs -n calico-system daemonset/calico-node -c calico-node
```

> **Tập tiếp theo:** Lab 1 thực chiến — "Pod thiếu label" connection timeout bí ẩn.
