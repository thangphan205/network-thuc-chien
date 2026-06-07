---
marp: true
theme: default
paginate: true
style: |
  section { font-family: 'Segoe UI', sans-serif; font-size: 22px; background: #0d1021; color: #e2e8f0; }
  h1 { color: #a78bfa; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #34d399; font-size: 1.4em; border-bottom: 2px solid #34d399; padding-bottom: 0.2em; }
  h3 { color: #fbbf24; font-size: 1.1em; }
  code { background: #1a1a35; color: #a0e4b8; padding: 2px 6px; border-radius: 0px; }
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
## Cilium + Istio: Khi nào kết hợp, khi nào dùng Cilium thuần?

**Phần 3 — Cilium** · `#cilium` `#istio` `#servicemesh` `#mTLS` `#tradeoffs`

---

## Mục tiêu tập này

- Cilium làm gì, Istio làm gì — phân biệt responsibilities
- 3 scenarios: Cilium only / Istio only / Cilium + Istio
- Overhead của Istio sidecar vs Cilium service mesh
- Decision matrix: chọn tool phù hợp use case

**Prerequisites:** Cilium đang chạy (từ Tập 24)

---

## Cilium vs Istio: Phân biệt vai trò

| Capability | Cilium | Istio |
| :--- | :--- | :--- |
| L3/L4 NetworkPolicy | ✅ | ❌ |
| L7 HTTP filtering | ✅ (basic path/method) | ✅ (full) |
| mTLS between services | ⚠️ (mesh mode) | ✅ (auto) |
| Traffic splitting (canary) | ❌ | ✅ |
| Circuit breaker | ❌ | ✅ |
| Retry policies | ❌ | ✅ |
| Observability | ✅ Hubble | ✅ Jaeger |
| Overhead | ~0 (BPF) | High (+50MB/pod) |

---

## Khi nào Cilium Only là đủ?

```
Cilium only phù hợp:
  ✅ Cần NetworkPolicy tốt hơn Calico/Flannel
  ✅ Cần L7 HTTP filtering đơn giản
  ✅ Cần DNS egress control (toFQDNs)
  ✅ Cần observability tốt (Hubble)
  ✅ Resource constrained (không có RAM cho sidecar)
  ✅ Latency-sensitive microservices

Cilium KHÔNG phù hợp:
  ❌ Cần traffic splitting (canary, blue-green)
  ❌ Cần automatic mTLS giữa services
  ❌ Cần circuit breaker tại application level
  ❌ Cần distributed tracing end-to-end
```

---

## Khi nào Cilium + Istio?

```
Kết hợp cho best of both worlds:
  Cilium:  CNI + L3/L4 policy + Hubble observability
  Istio:   Traffic management + mTLS + circuit breaker

Cilium replace kube-proxy:
  Cilium handle Service load balancing (XDP/BPF)
  → Istio không cần manage Service networking
  → Istio chỉ lo Envoy sidecar (application layer)

Tốt cho:
  ✅ Large microservices needing full service mesh features
  ✅ Compliance cần mTLS everywhere
  ✅ Blue-green deployment + advanced traffic routing
  ✅ Khi đã có Istio nhưng muốn better network policy

Cả 2 cùng tồn tại, không conflict:
  Cilium installed first (CNI layer)
  → Istio installed on top (service mesh layer)
```

---

## Cilium Service Mesh: Istio replacement?

```
Cilium 1.12+ có Cilium Service Mesh:
  ✅ mTLS giữa services (WireGuard hoặc TLS)
  ✅ Traffic management (header-based routing)
  ✅ Load balancing algorithms
  ✅ Egress control
  ✅ Hubble observability

Không có (hoặc limited):
  ⚠️  Circuit breaker (experimental)
  ⚠️  Retry policies (limited)
  ⚠️  Traffic mirroring

Verdict 2026:
  Cilium Service Mesh = "sidecar-less service mesh"
  Tốt cho 80% use cases
  Large teams với service mesh expertise → Istio
  Small/medium teams muốn simplicity → Cilium Mesh
```

---

## Decision Matrix

```
Bắt đầu từ câu hỏi:
  "Tôi cần gì ngoài NetworkPolicy?"
  
  Không cần gì thêm:
    → Cilium only
  
  Cần canary/blue-green hoặc circuit breaker:
    → Cilium + Istio
  
  Cần mTLS everywhere (compliance):
    → Cilium + Istio (hoặc Cilium Mesh mode)
  
  Cần distributed tracing (Jaeger):
    → Cilium + Istio
  
  Resource constrained (< 512MB free per pod):
    → Cilium only (Istio: +50MB RAM per pod)

Đừng add Istio "phòng khi cần":
  Overhead thực sự! +50MB RAM × 100 pods = +5GB RAM
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Verify Cilium + Istio không conflict

Chúng ta sẽ thực hành:

1. **Verify Cilium running** — baseline status.
2. **Install Istio minimal** (nếu muốn, optional — tốn tài nguyên lab).
3. **Verify không conflict** — Cilium pods vẫn Running sau Istio install.
4. **Deploy pod với sidecar** — xem Cilium và Istio cùng manage endpoint.
5. **Compare overhead** — xem RAM usage pod với/không có sidecar.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 33):** Hubble CLI — `hubble observe` debug real-time không cần SSH vào Pod.
