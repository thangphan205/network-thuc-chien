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

# Tập 30
## L7 Policy: Chặn HTTP POST theo path với Envoy Proxy

**Phần 3 — Cilium** · `#L7policy` `#HTTP` `#envoy` `#cilium` `#path-filtering`

---

## Mục tiêu tập này

- L7 policy trong Cilium: tại sao cần và cách hoạt động
- Envoy proxy được inject như thế nào khi enable L7
- Viết policy filter theo HTTP method + path (regex)
- Demo: GET /api/* ALLOWED, POST /admin/* BLOCKED với HTTP 403

**Prerequisites:** Cilium đang chạy (từ Tập 24)

---

## Tại sao cần L7 Policy?

```
Scenario thực tế:
  Frontend có thể GET /api/products     ← OK
  Frontend KHÔNG được POST /admin/users ← Phải block!

Với K8s NetworkPolicy (L4 only):
  Allow TCP:8080 từ frontend → backend
  → Frontend GET /api ✅
  → Frontend POST /admin ✅  ← Policy không biết HTTP!

Với Cilium L7 policy:
  Allow GET /api/* từ frontend
  Block POST /admin/* từ mọi nguồn (trừ admin pod)
  
Granularity mà iptables không thể làm!
```

---

## Envoy Proxy: Cơ chế L7 enforcement

```
Khi L7 rule detect → Cilium inject Envoy proxy:

Normal path (L4 only):
  Pod A → TC BPF → Pod B  (direct)

L7 path:
  Pod A → TC BPF → Envoy proxy → Pod B
                       │
                  Inspect HTTP headers
                  → match rule? → forward
                  → no match?  → 403 Forbidden

Envoy là sidecar-less:
  Không inject vào Pod.
  Chạy trên host network namespace.
  BPF redirect traffic vào Envoy transparent.

Response khi bị block:
  L4 block: TCP RST / timeout (dev không biết gì)
  L7 block: HTTP 403 Forbidden (dev thấy ngay lỗi gì!)
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
          path: "/.*"         # Allow ALL GET (regex)
        - method: POST
          path: "/api/.*"     # Allow POST /api/* only
        # Không có rule cho POST /admin/* → tự động DENY → HTTP 403
```

---

## L7 Policy tradeoffs

```
Ưu điểm:
  ✅ Fine-grained HTTP control (method + path regex)
  ✅ HTTP 403 thay vì timeout → developer thấy ngay
  ✅ Hubble log HTTP path/method/status code
  ✅ Sidecar-less: không thêm container vào Pod

Nhược điểm:
  ⚠️  Thêm Envoy hop → +0.1-0.2ms latency per request
  ⚠️  Chỉ HTTP/gRPC/Kafka — không phải arbitrary protocol
  ⚠️  Regex path matching — cẩn thận syntax

Khi nào dùng:
  → Cần block specific API endpoints (admin, payment)
  → Compliance yêu cầu L7 audit trail
  → Microservices với rõ ràng API contract
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Apply L7 Policy và verify HTTP 403

Chúng ta sẽ thực hành:

1. **Deploy HTTP server thực** (Python SimpleHTTPServer) làm backend.
2. **Verify không có policy:** GET và POST đều accessible.
3. **Apply L7 CiliumNetworkPolicy:** Allow GET /*, allow POST /api/*, block POST /admin/*.
4. **Test và xem HTTP 403** (không phải timeout) khi POST /admin.
5. **Hubble observe HTTP flows** — thấy path và status code.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 31):** DNS Policy với toFQDNs — Filter theo domain thay vì IP, giải quyết CDN multi-IP trap.
