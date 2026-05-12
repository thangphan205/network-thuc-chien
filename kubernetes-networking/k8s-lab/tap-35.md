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

# Tập 35
## Cilium + Istio: Khi nào kết hợp, khi nào dùng Cilium thuần?

**Phần 3 — Cilium** · `#cilium` `#istio` `#servicemesh` `#mTLS` `#tradeoffs`

---

## Mục tiêu tập này

- Cilium làm gì, Istio làm gì — phân biệt responsibilities
- 3 scenarios: Cilium only, Istio only, Cilium + Istio
- Overhead của Istio sidecar vs Cilium service mesh
- Cilium Mesh mode — Istio replacement?

---

## Cilium vs Istio: Khác nhau gì?

```
Cilium (CNI + Network Policy):
  Layer: L3/L4/L7 (HTTP/gRPC)
  mTLS: Optional (WireGuard node-to-node)
  Tracing: Hubble (network level)
  Circuit breaker: Không
  Retries: Không
  Traffic splitting: Không (cần Gateway API)
  Overhead: Zero (BPF, không có sidecar)

Istio (Service Mesh):
  Layer: L7 (application-aware)
  mTLS: Automatic (Envoy sidecar-to-sidecar)
  Tracing: Jaeger/Zipkin integration
  Circuit breaker: ✅ (Envoy)
  Retries: ✅ (Envoy retry policy)
  Traffic splitting: ✅ (VirtualService)
  Overhead: +50MB RAM per pod, +1-2ms latency
```

---

## Khi nào Cilium Only là đủ?

```
Cilium only phù hợp khi:
  ✅ Cần NetworkPolicy (L3/L4) tốt hơn Calico/Flannel
  ✅ Cần L7 HTTP filtering đơn giản (method/path)
  ✅ Cần DNS egress control (toFQDNs)
  ✅ Cần observability tốt (Hubble)
  ✅ Resource constrained (không có RAM cho sidecar)
  ✅ Latency-sensitive microservices

Cilium KHÔNG phù hợp khi:
  ❌ Cần traffic splitting (canary, blue-green)
  ❌ Cần automatic mTLS giữa services
  ❌ Cần circuit breaker tại application level
  ❌ Cần distributed tracing end-to-end
```

---

## Khi nào Cilium + Istio?

```
Kết hợp cho best of both worlds:
  Cilium: CNI + L3/L4 policy + Hubble
  Istio: Application-level features

Cilium replace kube-proxy:
  Cilium handle Service load balancing (XDP/BPF)
  → Istio không cần manage Service networking
  → Istio chỉ lo Envoy sidecar

Tốt cho:
  ✅ Large microservices needing all service mesh features
  ✅ Compliance cần mTLS everywhere
  ✅ Blue-green deployment của nhiều services
  ✅ Khi đã có Istio nhưng muốn better network policy

Cách triển khai:
  Cilium installed first (CNI)
  → Istio installed on top (service mesh layer)
  → Cả 2 cùng tồn tại, không conflict
```

---

## Cilium Service Mesh: Istio replacement?

```
Cilium 1.12+ có Cilium Service Mesh:
  ✅ mTLS giữa services (dùng WireGuard hoặc TLS)
  ✅ Traffic management (header-based routing)
  ✅ Load balancing algorithms (LeastConnections, etc)
  ✅ Egress control
  ✅ Hubble observability

Không có (hoặc limited):
  ⚠️  Circuit breaker (experimental)
  ⚠️  Retry policies (limited vs Envoy)
  ⚠️  Traffic mirroring (không phải production-ready)

Verdict 2026:
  Cilium Service Mesh = "sidecar-less service mesh"
  Tốt cho 80% use cases, Istio cho 20% còn lại
  Large teams với service mesh expertise → Istio
  Small/medium teams muốn simplicity → Cilium Mesh
```

---

## Lab: Verify Cilium không conflict với Istio

```bash
multipass shell k8s-master

# Verify Cilium running
kubectl -n kube-system get pods -l k8s-app=cilium
# All Running ✅

# Install Istio (minimal, demo profile)
curl -L https://istio.io/downloadIstio | sh -
cd istio-*/
export PATH=$PWD/bin:$PATH

istioctl install --set profile=minimal -y
# ✅ Istio core installed

# Verify Istio running
kubectl -n istio-system get pods
# istiod-xxxxx  1/1  Running  ✅

# Cilium vẫn running?
kubectl -n kube-system get pods -l k8s-app=cilium
# All still Running ✅ — không conflict!
```

---

## Lab: Deploy service với Istio sidecar

```bash
# Enable sidecar injection cho namespace
kubectl label namespace production istio-injection=enabled

# Deploy backend
kubectl apply -n production -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend-istio
  labels: {app: backend-istio}
spec:
  containers:
  - name: app
    image: python:3.11-alpine
    command: ["python3", "-m", "http.server", "8080"]
EOF

kubectl -n production wait --for=condition=Ready \
  pod/backend-istio --timeout=90s

# Xem sidecar được inject
kubectl -n production describe pod backend-istio | grep "istio-proxy"
# istio-proxy:  ← Envoy sidecar đang chạy!

# Cilium vẫn manage networking
kubectl -n kube-system exec -it \
  $(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1) \
  -- cilium endpoint list | grep backend-istio
# Endpoint có trong Cilium list ✅
```

---

## Key Takeaways

**Decision matrix:**

| Need | Cilium | Istio | Both |
| :--- | :--- | :--- | :--- |
| NetworkPolicy | ✅ | ❌ | ✅ |
| L7 HTTP filter | ✅ (basic) | ✅ (full) | ✅ |
| mTLS between services | ⚠️ (mesh mode) | ✅ | ✅ |
| Traffic splitting | ❌ | ✅ | ✅ |
| Circuit breaker | ❌ | ✅ | ✅ |
| Observability | ✅ (Hubble) | ✅ (Jaeger) | ✅✅ |
| Resource overhead | ~0 | High | High |

```
Bắt đầu với Cilium only.
Add Istio chỉ khi cần features mà Cilium không có.
Đừng add Istio "phòng khi cần" — overhead thực sự!
```

> **Tập tiếp theo (Tập 36): Hubble CLI — `hubble observe` debug real-time không cần SSH vào Pod.**
