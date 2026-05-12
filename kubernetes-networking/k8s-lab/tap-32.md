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

# Tập 32
## L3/L4 Policy trong Cilium: So sánh với Kubernetes NetworkPolicy

**Phần 3 — Cilium** · `#CiliumNetworkPolicy` `#L3` `#L4` `#NetworkPolicy` `#policy`

---

## Mục tiêu tập này

- CiliumNetworkPolicy vs Kubernetes NetworkPolicy: khi nào dùng cái nào
- Cilium vẫn support K8s NetworkPolicy (backward compatible)
- Extensions của CiliumNetworkPolicy ở L3/L4
- Lab áp dụng policy với Cilium-specific features

---

## Cilium vẫn support K8s NetworkPolicy

```bash
# Cilium fully implement K8s NetworkPolicy spec
# Bất kỳ NetworkPolicy nào chạy với Calico đều chạy được với Cilium

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: production
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
    - protocol: TCP
      port: 8080
EOF

# Works! Cilium compile này → BPF policy map
# Không cần iptables, không cần felix
```

---

## CiliumNetworkPolicy: Extensions L3

```yaml
# K8s NetworkPolicy: chỉ dùng được label selector
# CiliumNetworkPolicy: thêm CIDR, entity, DNS

apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-specific-cidr
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromCIDR:
    - "192.168.64.0/24"    # Allow từ monitoring network
  - fromEntities:
    - "cluster"            # Allow toàn bộ cluster traffic
    - "host"               # Allow từ Node host
    - "world"              # Allow từ external (internet)
```

---

## CiliumNetworkPolicy: Extensions L4

```yaml
# K8s NetworkPolicy: chỉ TCP/UDP port
# CiliumNetworkPolicy: thêm ICMP, protocol cụ thể

apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-icmp-ping
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - icmps:
    - fields:
      - type: 8    # ICMP Echo Request (ping)
        family: IPv4
  - toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:       # L7! — discussed in tap-33
        - method: GET
          path: "/health"
```

---

## Entity selector: Powerful shorthand

```
Cilium entities = predefined groups:

"cluster"  = tất cả Pod/Service trong cluster
"host"     = Node host network namespace
"world"    = Bất kỳ IP ngoài cluster (internet)
"remote-node" = Node khác trong cluster (không phải local)
"kube-apiserver" = K8s API server (special entity)

Ứng dụng thực tế:
  # Cho phép DNS (kube-dns là cluster internal)
  egress:
  - toEntities:
    - "cluster"      # kube-dns là cluster entity
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP

  # Block toàn bộ internet, chỉ allow cluster-internal
  egress:
  - toEntities:
    - "cluster"
  # (default deny world = không có rule cho world = DENY)
```

---

## Lab Setup

```bash
multipass shell k8s-master

kubectl create namespace production 2>/dev/null || true

# Deploy backend và frontend
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
---
apiVersion: v1
kind: Pod
metadata:
  name: external-client
  labels: {app: external}
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

kubectl -n production wait --for=condition=Ready \
  pod/backend pod/frontend pod/external-client --timeout=60s
```

---

## Lab: Apply và test CiliumNetworkPolicy

```bash
BACKEND_IP=$(kubectl -n production get pod backend \
  -o jsonpath='{.status.podIP}')

# Apply default deny + Cilium-specific CIDR allow
kubectl apply -n production -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-policy
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend    # Label-based (same as K8s NetworkPolicy)
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
EOF

# Test: frontend → backend (should work)
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080
# Connection succeeded ✅

# Test: external-client → backend (should fail)
kubectl -n production exec external-client -- nc -zv $BACKEND_IP 8080
# (timeout) ✅ Blocked!
```

---

## Lab: Xem policy via Hubble

```bash
# Port-forward Hubble relay
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Xem flow khi external-client bị block
hubble observe \
  --namespace production \
  --verdict DROPPED \
  --follow &

# Generate traffic
kubectl -n production exec external-client -- \
  nc -zv $BACKEND_IP 8080 &

# Hubble output:
# production/external-client → production/backend:8080
# DROPPED  Policy denied
```

---

## Key Takeaways

**K8s NetworkPolicy vs CiliumNetworkPolicy:**

| Feature | K8s NetworkPolicy | CiliumNetworkPolicy |
| :--- | :--- | :--- |
| Label selector | ✅ | ✅ |
| CIDR | ✅ (egress only) | ✅ (both) |
| Entity (cluster/world/host) | ❌ | ✅ |
| ICMP type filtering | ❌ | ✅ |
| L7 (HTTP/DNS/gRPC) | ❌ | ✅ |
| DNS FQDN | ❌ | ✅ |

```
Rule of thumb:
  K8s NetworkPolicy → dùng khi cần portability (multi-CNI)
  CiliumNetworkPolicy → dùng khi cần entity/CIDR/L7 features
  
  Cilium hỗ trợ CẢ HAI cùng lúc trong cùng cluster!
```

> **Tập tiếp theo (Tập 33): L7 Policy — Chặn HTTP POST theo path với Envoy Proxy.**
