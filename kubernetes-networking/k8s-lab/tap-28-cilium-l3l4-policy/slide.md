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

# Tập 28
## L3/L4 Policy trong Cilium: So sánh với Kubernetes NetworkPolicy

**Phần 3 — Cilium** · `#CiliumNetworkPolicy` `#L3` `#L4` `#NetworkPolicy` `#policy`

---

## Mục tiêu tập này

- CiliumNetworkPolicy vs Kubernetes NetworkPolicy: khi nào dùng cái nào
- Cilium vẫn support K8s NetworkPolicy (backward compatible)
- Extensions của CiliumNetworkPolicy ở L3/L4
- Entity selector: `cluster`, `host`, `world` — powerful shorthand

**Prerequisites:** Cilium đang chạy (từ Tập 23)

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
# Works! Cilium compile → BPF policy map (không cần iptables)
```

---

## CiliumNetworkPolicy: Extensions L3

```yaml
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

## Entity selector: Powerful shorthand

```
Cilium entities = predefined groups:
  "cluster"      = tất cả Pod/Service trong cluster
  "host"         = Node host network namespace
  "world"        = IP ngoài cluster (internet)
  "remote-node"  = Node khác trong cluster
  "kube-apiserver" = K8s API server

Ví dụ thực tế — allow DNS:
  egress:
  - toEntities:
    - "cluster"      # kube-dns là cluster entity
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP

Block internet, chỉ allow cluster-internal:
  egress:
  - toEntities:
    - "cluster"
  # (default deny = không có rule cho "world" = DENY world)
```

---

## CiliumNetworkPolicy: Extensions L4 — ICMP

```yaml
# K8s NetworkPolicy: chỉ TCP/UDP port
# CiliumNetworkPolicy: thêm ICMP filtering

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
      - type: 8        # ICMP Echo Request (ping)
        family: IPv4
  - toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
```

---

## K8s NetworkPolicy vs CiliumNetworkPolicy

| Feature | K8s NetworkPolicy | CiliumNetworkPolicy |
| :--- | :--- | :--- |
| Label selector | ✅ | ✅ |
| CIDR (ingress) | ✅ | ✅ |
| CIDR (egress) | ✅ | ✅ |
| Entity (cluster/world/host) | ❌ | ✅ |
| ICMP type filtering | ❌ | ✅ |
| L7 (HTTP/DNS/gRPC) | ❌ | ✅ |
| DNS FQDN | ❌ | ✅ |

```
Rule of thumb:
  K8s NetworkPolicy → portability (multi-CNI environments)
  CiliumNetworkPolicy → entity/CIDR/L7 features
  Cilium hỗ trợ CẢ HAI cùng lúc trong cùng cluster!
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Apply CiliumNetworkPolicy và xem qua Hubble

Chúng ta sẽ thực hành:

1. **Deploy backend/frontend/external-client** trong namespace `production`.
2. **Apply K8s NetworkPolicy** — verify Cilium compile sang BPF (không iptables).
3. **Apply CiliumNetworkPolicy** với `fromEntities` — verify entity selector.
4. **Xem flows trong Hubble** — `hubble observe --verdict DROPPED`.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 29):** L7 Policy — Chặn HTTP POST theo path với Envoy Proxy.
