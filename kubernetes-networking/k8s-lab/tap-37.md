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

# Tập 37
## Hubble UI: Service Map tự động & DROPPED màu đỏ

**Phần 3 — Cilium** · `#hubble` `#UI` `#servicemap` `#visualization` `#observability`

---

## Mục tiêu tập này

- Hubble UI cung cấp gì mà CLI không có
- Service Map: tự động vẽ topology từ real traffic
- Đọc visual flows: xanh (forwarded) vs đỏ (dropped)
- Lab: mở Hubble UI và trace một incident trực quan

---

## Hubble UI là gì?

```
Hubble UI = Web dashboard cho Hubble data

Features:
  ┌──────────────────────────────────────────────┐
  │  Service Map (tự động generated từ traffic)  │
  │                                              │
  │  [frontend] ──────▶ [backend]                │
  │      │               ↑                       │
  │      └──────────X──▶ [database]              │
  │                 (RED = DROPPED)              │
  │                                              │
  │  Filter: namespace, pod, verdict             │
  │  Timeline: flow history                      │
  │  Detail: click edge để xem packets           │
  └──────────────────────────────────────────────┘

Không cần cấu hình! Hubble tự vẽ từ observed traffic.
```

---

## Service Map: Tự động từ real traffic

```
Khi bạn có:
  frontend → backend → database
  prometheus → backend (scrape metrics)
  frontend → external-api.com

Hubble UI tự động:
  1. Observe tất cả flows
  2. Group theo Service/Pod label
  3. Draw edges với color:
     GREEN  = Majority forwarded
     YELLOW = Some dropped
     RED    = Majority dropped
  4. Edge thickness = traffic volume

Không cần:
  - Vẽ tay topology
  - Cập nhật khi service thêm/xóa
  - Config gì cả

"Cluster tự document network topology của nó"
```

---

## Lab: Mở Hubble UI

```bash
multipass shell k8s-master

# Verify Hubble UI running
kubectl -n kube-system get pods | grep hubble-ui
# hubble-ui-xxxxx  2/2  Running

# Port-forward UI
kubectl -n kube-system port-forward svc/hubble-ui 12000:80 &
echo "Hubble UI: http://localhost:12000"

# Nếu chạy trong Multipass, cần tunnel từ macOS:
MASTER_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
# Trên macOS: ssh -L 12000:localhost:12000 ubuntu@$MASTER_IP
# (nếu không có ssh, dùng multipass exec)
```

---

## Lab: Generate traffic để xem Service Map

```bash
# Setup namespace và pods
kubectl create namespace production 2>/dev/null || true

kubectl apply -n production -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels: {app: frontend, tier: web}
spec:
  containers:
  - {name: app, image: nicolaka/netshoot, command: ["sleep","infinity"]}
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels: {app: backend, tier: api}
spec:
  containers:
  - {name: app, image: nicolaka/netshoot, command: ["nc","-lk","-p","8080"]}
---
apiVersion: v1
kind: Pod
metadata:
  name: database
  labels: {app: database, tier: data}
spec:
  containers:
  - {name: app, image: nicolaka/netshoot, command: ["nc","-lk","-p","5432"]}
EOF

kubectl -n production wait --for=condition=Ready \
  pod/frontend pod/backend pod/database --timeout=90s

BACKEND_IP=$(kubectl -n production get pod backend \
  -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl -n production get pod database \
  -o jsonpath='{.status.podIP}')
```

---

## Lab: Simulate traffic patterns

```bash
# Generate normal traffic (frontend → backend)
kubectl -n production exec frontend -- bash -c "
  while true; do
    nc -zv $BACKEND_IP 8080 &>/dev/null
    sleep 0.5
  done
" &

# Apply NetworkPolicy: block direct frontend → database
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-frontend-db
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - {protocol: TCP, port: 5432}
EOF

# Simulate frontend trying to reach database directly (will be dropped)
kubectl -n production exec frontend -- bash -c "
  while true; do
    nc -zv $DB_IP 5432 &>/dev/null
    sleep 1
  done
" &
```

---

## Lab: Đọc Hubble UI

```bash
# Mở browser: http://localhost:12000
# Chọn namespace: production

# Hubble UI sẽ show:
#
#   [frontend] ──GREEN──▶ [backend]     ← traffic đang chạy OK
#       │
#       └──RED──▶ [database]            ← traffic bị DROP!
#
# Click vào edge RED:
#   Flows list: frontend → database:5432  DROPPED  Policy denied
#   Count: 42 drops in last 1 minute
#
# Click vào node [frontend]:
#   Egress flows: all flows going out from frontend
#   Ingress flows: all flows coming into frontend

# Từ UI → hiểu ngay:
#   frontend không được phép connect trực tiếp database
#   Phải qua backend (đúng architecture!)
```

---

## Hubble UI: Các view quan trọng

```
1. Service Map View:
   Tổng quan topology, màu sắc alert
   Best for: "Cluster của tôi đang làm gì?"

2. Flow List View (click edge):
   Chi tiết từng packet: src → dst, verdict, timestamp
   Best for: "Tại sao connection này bị drop?"

3. Filter Bar:
   namespace, pod name, verdict, protocol, IP
   Best for: Focus vào 1 service trong cluster lớn

4. Namespace selector (top):
   Switch namespace để xem topology riêng
   Best for: Multi-tenant cluster

Tips:
   - CTRL+click để multi-select nodes
   - Flow list có timestamp → correlate với logs
   - Export JSON từ flow list để ticket/postmortem
```

---

## Key Takeaways

```
Hubble UI vs CLI:

hubble observe CLI:
  Tốt cho: scripting, CI/CD, quick checks
  Pattern: "give me flows matching X"

Hubble UI:
  Tốt cho: onboarding, incident review, architecture review
  Pattern: "show me what's happening visually"

Service Map giải quyết "do you know your cluster?":
  Old way: draw Visio diagram, keep updated manually
  New way: hubble observe → auto-generated map

RED edges = immediate action items:
  Click → see which policy is causing drops
  Fix policy → watch edge turn GREEN in real-time

Zero-config: Hubble UI auto-generates từ observed traffic
  No instrumentation needed in application code!
```

> **Tập tiếp theo (Tập 38): Hubble Metrics — hubble_drop_total, http_requests và đúng tool đúng tình huống.**
