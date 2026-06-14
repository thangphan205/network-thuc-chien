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
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 43
## Gateway API + Cilium Ingress — North-South Traffic Production-Ready

**Phần 3 — Cilium** · `#gatewayapi` `#ingress` `#north-south` `#routing` `#canary`

---

## Ingress vs Gateway API

```
Ingress (cũ - Kubernetes 1.0 era):
  
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  ↑ Monolithic: infra config + routing rules trộn lẫn
  ↑ Annotations không standardized (nginx.ingress.kubernetes.io/...)
  ↑ Cluster operator và app developer dùng chung 1 resource
  ↑ Limited: chỉ HTTP/HTTPS, không có traffic weighting chuẩn

Gateway API (mới - GA từ K8s 1.28):

  GatewayClass  ← Cluster operator quản lý (infrastructure)
  Gateway       ← Cluster operator quản lý (listener: port, protocol)
  HTTPRoute     ← App developer quản lý (routing rules)
  
  ↑ Separation of concerns: infra vs application
  ↑ Standardized across providers (Cilium, Nginx, Istio, Envoy)
  ↑ Rich routing: path, header, weight, method
  ↑ TLS termination + HTTPS redirect built-in
```

---

## Gateway API Resources

```yaml
# GatewayClass: "Loại gateway nào?" (cluster admin)
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
  # Cilium tự tạo GatewayClass này khi gatewayAPI.enabled=true

---
# Gateway: "Nghe ở port nào?" (cluster admin)
kind: Gateway
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    port: 80
    protocol: HTTP
  # → Cilium tạo Service type=LoadBalancer với IP từ LB IPAM pool

---
# HTTPRoute: "Route traffic đi đâu?" (app developer)
kind: HTTPRoute
spec:
  parentRefs: [{name: cilium-gateway}]
  rules:
  - matches: [{path: {value: /api}}]
    backendRefs: [{name: backend-svc, port: 8080}]
```

---

## Routing Patterns: Path + Header + Weight

```yaml
# Pattern 1: Path-based routing
rules:
- matches: [{path: {type: PathPrefix, value: /api}}]
  backendRefs: [{name: api-svc, port: 8080}]
- matches: [{path: {type: PathPrefix, value: /}}]
  backendRefs: [{name: frontend-svc, port: 3000}]

# Pattern 2: Header-based (canary deployment)
rules:
- matches:
  - path: {value: /api}
    headers: [{name: X-Version, value: v2}]
  backendRefs: [{name: api-v2-svc, port: 8080}]  # Canary
- matches: [{path: {value: /api}}]
  backendRefs: [{name: api-v1-svc, port: 8080}]  # Stable

# Pattern 3: Traffic weighting (gradual rollout)
rules:
- matches: [{path: {value: /api}}]
  backendRefs:
  - {name: api-v1-svc, port: 8080, weight: 90}  # 90% stable
  - {name: api-v2-svc, port: 8080, weight: 10}  # 10% canary
```

---

## Cilium Gateway API: Sidecar-less Architecture

```
Nginx Ingress Controller:
  External → Nginx Pod (separate deployment) → Service → Pod
  Resources: 1 Nginx pod = ~50-100MB RAM per replica
  Config: nginx.conf generated from annotations
  
Cilium Gateway API:
  External → Cilium eBPF (built-in every node) → Pod
  Resources: 0 extra pods, routing in BPF programs
  Config: HTTPRoute compiled to BPF/Envoy rules

Tradeoff:
  Nginx: Mature, rich ecosystem, many extensions
  Cilium: Zero overhead, Hubble observable, integrated policy
  
  Production choice:
  ✅ New cluster → Cilium Gateway API (simpler)
  ✅ Complex rewrite rules → Nginx Ingress
  ✅ Service mesh needed → Istio + Gateway API
```

---

## TLS Termination

```yaml
# Tạo Secret từ cert:
kubectl create secret tls my-tls \
  --cert=cert.pem --key=key.pem

# Gateway với HTTPS listener:
kind: Gateway
spec:
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate          # TLS terminated here
      certificateRefs:
      - kind: Secret
        name: my-tls
  - name: http-redirect
    port: 80
    protocol: HTTP

# HTTP → HTTPS redirect:
kind: HTTPRoute
spec:
  parentRefs: [{sectionName: http-redirect}]
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
```

---

## So sánh: Ingress vs Gateway API vs Istio VirtualService

| Feature | Ingress | Gateway API | Istio VirtualService |
| :--- | :--- | :--- | :--- |
| **Path routing** | ✅ | ✅ | ✅ |
| **Header routing** | ⚠️ annotation | ✅ native | ✅ |
| **Traffic weight** | ⚠️ annotation | ✅ native | ✅ |
| **TLS termination** | ✅ | ✅ | ✅ |
| **gRPC routing** | ❌ | ✅ GRPCRoute | ✅ |
| **Cross-namespace** | ❌ | ✅ ReferenceGrant | ✅ |
| **Extra overhead** | Nginx pods | 0 (Cilium) | Envoy sidecars |
| **Standard spec** | K8s native | K8s native | Istio only |

---

<!-- _class: lab -->

## 🔬 Lab Time: Gateway API với Cilium

1. **Install Gateway API CRDs** + Enable trong Cilium Helm
2. **Deploy 3-tier app:** frontend, backend-v1, backend-v2
3. **Path routing:** `/` → frontend, `/api/*` → backend-v1
4. **Canary deployment:** header `X-Version: v2` → backend-v2
5. **Traffic splitting:** 80% v1, 20% v2 weighted routing
6. **HTTPS:** TLS termination + HTTP redirect

👉 **Xem chi tiết trong `lab-guide.md`**

> **Tập tiếp theo (Tập 44):** Upgrade + Day-2 Operations — không downtime
