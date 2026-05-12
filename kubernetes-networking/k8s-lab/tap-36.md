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

# Tập 36
## Hubble CLI: `hubble observe` — Debug real-time không cần SSH vào Pod

**Phần 3 — Cilium** · `#hubble` `#observability` `#CLI` `#debug` `#flows`

---

## Mục tiêu tập này

- Hubble là gì và tại sao nó thay đổi cách debug
- Cài hubble CLI và kết nối với cluster
- 10+ command patterns quan trọng nhất
- Lab: debug "connection refused" với Hubble trong 30 giây

---

## Hubble: Network observability built into Cilium

```
Trước Hubble (với Calico/Flannel):
  Debug "Pod A không kết nối được Pod B":
  1. SSH vào Node A
  2. kubectl exec -it podA -- bash
  3. tcpdump -i eth0 ...   (cần quyền)
  4. iptables -L ... | grep ...
  5. Đọc log Felix ...
  → 15-30 phút mỗi incident

Với Hubble:
  hubble observe --pod production/pod-a \
    --verdict DROPPED --follow
  → Thấy ngay: "Policy denied: pod-a → pod-b:8080"
  → 30 giây!

Hubble = network flow recorder + query engine
Record EVERY packet decision trong cluster!
```

---

## Hubble Architecture

```
┌─────────────────────────────────────────────────┐
│               Cilium Agent (Node)               │
│                                                 │
│  BPF Programs ──── record flow ────▶ Ring Buffer│
│  (per packet decision)               (4096 events│
│                                       per node) │
│                   ▲                             │
│                   │ expose via gRPC             │
│             Hubble Server                       │
└─────────────────────────────────────────────────┘
         ▲ gRPC
  ┌──────┴───────┐
  │ Hubble Relay │  ← Aggregate flows from ALL nodes
  └──────┬───────┘
         ▲ gRPC
  ┌──────┴───────┐
  │  hubble CLI  │  ← Your terminal
  └──────────────┘
```

---

## Setup: hubble CLI

```bash
# Trên macOS (local machine):
brew install hubble

# Verify Hubble Relay running trong cluster
kubectl -n kube-system get pods | grep hubble
# hubble-relay-xxxxx   1/1  Running
# hubble-ui-xxxxx      2/2  Running

# Port-forward Hubble Relay
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Test connection
hubble status
# Healthcheck (via localhost:4245): Ok
# Current/Max Flows: 4096/4096 (100%)
# Flows/s: 42.3
```

---

## Quan trọng nhất: hubble observe

```bash
# Basic: xem tất cả flows
hubble observe

# Filter theo namespace
hubble observe --namespace production

# Chỉ xem DROPPED flows
hubble observe --verdict DROPPED

# Chỉ xem FORWARDED flows
hubble observe --verdict FORWARDED

# Filter theo Pod
hubble observe --pod production/frontend

# Từ Pod này đến Pod kia
hubble observe --from-pod production/frontend \
               --to-pod production/backend

# Follow real-time (như tail -f)
hubble observe --follow --verdict DROPPED

# HTTP flows only
hubble observe --protocol http
```

---

## Output format: Đọc Hubble output

```
$ hubble observe --namespace production --verdict DROPPED

# Format:
# TIMESTAMP    SOURCE                DEST               VERDICT   REASON
# 14:23:05.123 production/frontend   production/backend  DROPPED   Policy denied
# 14:23:05.124 production/frontend   10.96.0.10:53      FORWARDED
# 14:23:07.891 production/attacker   production/backend  DROPPED   Policy denied

# Với --output json:
{
  "flow": {
    "time": "2026-05-12T14:23:05Z",
    "source": {"namespace": "production", "pod_name": "frontend"},
    "destination": {"namespace": "production", "pod_name": "backend"},
    "l4": {"TCP": {"destination_port": 8080}},
    "verdict": "DROPPED",
    "drop_reason": "Policy denied"
  }
}
```

---

## Lab: Debug trong 30 giây

```bash
# Setup: Deploy production stack
kubectl create namespace production 2>/dev/null || true

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
    command: ["nc", "-lk", "-p", "8080"]
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels: {app: frontend}
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

# Apply default deny (simulate production env)
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF

kubectl -n production wait --for=condition=Ready \
  pod/backend pod/frontend --timeout=60s
```

---

## Lab: Xem Hubble detect vấn đề

```bash
BACKEND_IP=$(kubectl -n production get pod backend \
  -o jsonpath='{.status.podIP}')

# Start Hubble observer trước
hubble observe --namespace production \
  --verdict DROPPED --follow &
HUBBLE_PID=$!

# Trigger connection từ frontend
kubectl -n production exec frontend -- \
  nc -zv $BACKEND_IP 8080 &>/dev/null &

# Hubble output xuất hiện ngay:
# production/frontend → production/backend:8080  DROPPED  Policy denied

# Không cần:
# - SSH vào node
# - kubectl exec với tcpdump
# - Đọc iptables rules

kill $HUBBLE_PID

# Fix: Allow frontend → backend
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - {protocol: TCP, port: 8080}
EOF

# Verify fix với Hubble
hubble observe --namespace production \
  --from-pod production/frontend \
  --to-pod production/backend &
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080
# Hubble: production/frontend → production/backend:8080  FORWARDED ✅
```

---

## Useful filters cheat sheet

```bash
# Xem tất cả egress bị drop (Pod đang gọi ra ngoài)
hubble observe --verdict DROPPED \
  --from-namespace production

# Xem HTTP 4xx/5xx
hubble observe --protocol http \
  --http-status-code 403

# Xem flows đến specific port
hubble observe --to-port 5432   # Database connections

# Xem flows từ IP cụ thể
hubble observe --from-ip 10.244.1.5

# JSON output cho parsing
hubble observe --output json --verdict DROPPED \
  | jq '.flow | {src: .source.pod_name, dst: .destination.pod_name}'

# Summary statistics
hubble observe --verdict DROPPED \
  | sort | uniq -c | sort -rn | head -10
```

---

## Key Takeaways

```
Hubble = tcpdump + iptables-L + prometheus, tất cả trong 1 command

hubble observe patterns quan trọng nhất:
  --verdict DROPPED          → Tìm bị chặn bởi policy
  --from-pod / --to-pod      → Trace specific connection
  --protocol http            → HTTP debugging
  --follow                   → Real-time monitoring
  --output json | jq         → Automation/scripting

vs Calico debugging:
  Calico: calicoctl + iptables + tcpdump = 3 tools
  Cilium: hubble observe = 1 command

Hubble không chỉ giúp debug — giúp HIỂU:
  "Ai đang gọi ai trong cluster của tôi?"
  hubble observe → network map của production!
```

> **Tập tiếp theo (Tập 37): Hubble UI — Service Map tự động và DROPPED màu đỏ.**
