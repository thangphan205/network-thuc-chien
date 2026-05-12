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

# Tập 33
## L7 Policy: Chặn HTTP POST theo path với Envoy Proxy

**Phần 3 — Cilium** · `#L7policy` `#HTTP` `#envoy` `#cilium` `#path-filtering`

---

## Mục tiêu tập này

- L7 policy trong Cilium: tại sao cần và cách hoạt động
- Envoy proxy được inject như thế nào khi enable L7
- Viết policy filter theo HTTP method + path
- Demo: cho phép GET /api nhưng block POST /admin

---

## Tại sao cần L7 Policy?

```
Scenario thực tế:
  Frontend có thể GET /api/products     ← OK
  Frontend KHÔNG được POST /admin/users ← Phải block!

Với K8s NetworkPolicy (L4 only):
  Allow TCP:8080 từ frontend → backend
  → Frontend GET /api ✅
  → Frontend POST /admin ✅ (policy không biết HTTP!)

Với Cilium L7 policy:
  Allow GET /api/* từ frontend
  Allow POST /api/* từ frontend
  Block /* /admin/* từ mọi nguồn (trừ admin pod)
  → Granularity mà iptables không thể làm!
```

---

## Envoy Proxy: L7 enforcement mechanism

```
Khi L7 rule detect → Cilium inject Envoy proxy:

Normal path (L4 only):
  Pod A → TC BPF → Pod B (direct)

L7 path:
  Pod A → TC BPF → Envoy proxy → Pod B
           │              │
           │    Envoy inspect HTTP headers
           │    → match rule? → forward
           │    → no match?  → 403 Forbidden
           │
           └─── BPF redirect traffic đến Envoy port

Envoy là sidecar-less! Không inject vào Pod.
Envoy chạy trên host network namespace,
được BPF redirect traffic vào.
```

---

## Viết L7 HTTP Policy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-l7-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: GET
          path: "/api/.*"      # Regex! GET /api/* OK
        - method: POST
          path: "/api/.*"      # POST /api/* OK
        # Không có rule cho /admin/* → tự động DENY
```

---

## Lab Setup: HTTP server thực sự

```bash
multipass shell k8s-master

kubectl create namespace production 2>/dev/null || true

# Deploy backend với HTTP server thực (python SimpleHTTP)
kubectl apply -n production -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels: {app: backend}
spec:
  containers:
  - name: app
    image: python:3.11-alpine
    command: ["python3", "-m", "http.server", "8080"]
    workingDir: "/tmp"
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

kubectl -n production wait --for=condition=Ready \
  pod/backend pod/frontend --timeout=60s

BACKEND_IP=$(kubectl -n production get pod backend \
  -o jsonpath='{.status.podIP}')
```

---

## Lab: Verify trước khi apply policy

```bash
# Kiểm tra trước: tất cả paths đều accessible
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  http://$BACKEND_IP:8080/
# 200 (OK, not blocked)

kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://$BACKEND_IP:8080/admin/users \
  -d '{}'
# 200 (OK, not blocked yet!)
```

---

## Lab: Apply L7 Policy và test

```bash
# Apply L7 policy
kubectl apply -n production -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-l7
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: GET
          path: "/.*"           # Allow GET để browse
        - method: POST
          path: "/api/.*"       # Allow POST /api only
EOF

# Test 1: GET / (should work)
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  http://$BACKEND_IP:8080/
# 200 ✅

# Test 2: POST /admin (should block!)
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://$BACKEND_IP:8080/admin/users
# 403 ✅ Forbidden! (Envoy return 403, not timeout!)
```

---

## Lab: Xem L7 events trong Hubble

```bash
# Hubble observe L7 events
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Watch flows
hubble observe \
  --namespace production \
  --protocol http \
  --follow &

# Generate mixed traffic
kubectl -n production exec frontend -- bash -c '
  curl -s http://'"$BACKEND_IP"':8080/ &>/dev/null
  curl -s -X POST http://'"$BACKEND_IP"':8080/api/users \
    -d "{}" &>/dev/null
  curl -s -X POST http://'"$BACKEND_IP"':8080/admin/users \
    -d "{}" &>/dev/null
'

# Hubble output:
# HTTP GET /           → 200 FORWARDED
# HTTP POST /api/users → 200 FORWARDED
# HTTP POST /admin/users → 403 DROPPED (Policy denied)
```

---

## Key Takeaways

```
L7 Policy với Cilium:
  Policy engine: BPF (detect L7 needed)
  L7 enforcement: Envoy proxy (không inject vào Pod)
  BPF redirect traffic → Envoy → inspect → forward/deny

Response khi bị block:
  L4 block (iptables/BPF): TCP RST hoặc timeout
  L7 block (Cilium+Envoy): HTTP 403 Forbidden
  → Developer thấy lỗi ngay! Không cần debug timeout

Tradeoff khi bật L7:
  ✅ Fine-grained HTTP control
  ✅ HTTP 403 thay vì timeout
  ✅ Hubble log HTTP path/method/status
  ⚠️  Thêm Envoy hop → +0.1-0.2ms latency
  ⚠️  Chỉ HTTP/gRPC, không phải arbitrary L7
```

> **Tập tiếp theo (Tập 34): DNS Policy với toFQDNs — Filter theo domain thay vì IP.**
