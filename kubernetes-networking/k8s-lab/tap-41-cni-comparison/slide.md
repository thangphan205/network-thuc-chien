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

# Tập 41
## So sánh 3 CNI: Flannel vs Calico vs Cilium — Bảng đánh giá toàn diện

**Phần 4 — Kết** · `#comparison` `#flannel` `#calico` `#cilium` `#decision`

---

## Mục tiêu tập này

- Đặt 3 CNI cạnh nhau trên mọi dimension quan trọng
- Performance numbers thực tế từ benchmark
- Maturity và community support
- Use case ngách: khi nào từng CNI win

**Prerequisites:** Đã hoàn thành Phần 1 (Flannel), Phần 2 (Calico), Phần 3 (Cilium)

---

## So sánh: Networking Foundation

| Feature | Flannel | Calico | Cilium |
| :--- | :--- | :--- | :--- |
| **Data plane** | VXLAN/host-gw | iptables/eBPF | eBPF (native) |
| **NetworkPolicy** | ❌ Không có | ✅ Full K8s spec | ✅ Full K8s + CiliumNP |
| **BGP** | ❌ | ✅ BIRD | ✅ GoBGP (built-in) |
| **Encryption** | ❌ | ✅ WireGuard | ✅ WireGuard |
| **Overlay** | VXLAN only | VXLAN/IPIP/none | VXLAN/Geneve/none |
| **IPv6** | ⚠️ Limited | ✅ | ✅ |

---

## So sánh: Policy Capabilities

| Feature | Flannel | Calico | Cilium |
| :--- | :--- | :--- | :--- |
| **L3/L4 policy** | ❌ | ✅ | ✅ |
| **L7 HTTP policy** | ❌ | ❌ | ✅ (Envoy) |
| **DNS policy (FQDN)** | ❌ | ⚠️ Limited | ✅ toFQDNs |
| **CIDR-based egress** | ❌ | ✅ | ✅ |
| **Entity (world/host)** | ❌ | ⚠️ | ✅ |
| **Default deny** | ❌ | ✅ | ✅ |
| **Policy scale** | N/A | O(n) iptables | O(1) BPF map |

---

## So sánh: Observability

| Feature | Flannel | Calico | Cilium |
| :--- | :--- | :--- | :--- |
| **Flow visibility** | ❌ | Manual tcpdump | ✅ Hubble |
| **Drop reason** | ❌ | ⚠️ iptables logs | ✅ Labeled reasons |
| **HTTP metrics** | ❌ | ❌ | ✅ Hubble Metrics |
| **Service map** | ❌ | ❌ | ✅ Hubble UI |
| **Prometheus** | Limited | ✅ Felix metrics | ✅ Hubble metrics |
| **Debug time** | N/A | Minutes | Seconds |

---

## So sánh: Performance Numbers

```
Benchmark: 3-node cluster, 1Gbps NIC, Linux 6.x
(Approximate, varies by hardware and workload)

Same-node Pod-to-Pod bandwidth:
  Flannel:  ~8 Gbps  (host-gw) / ~3 Gbps (VXLAN)
  Calico:   ~8 Gbps  (native)  / ~4 Gbps (IPIP)
  Cilium:   ~18 Gbps (sockops bypass!) / ~5 Gbps (VXLAN)

Cross-node latency (p99):
  Flannel:  ~0.4ms  (VXLAN overhead)
  Calico:   ~0.3ms  (native routing)
  Cilium:   ~0.25ms (eBPF TC, optimized path)

Policy throughput (1000 policies, 10k rules):
  Flannel:  N/A
  Calico:   ~2 Gbps  (iptables linear scan O(n))
  Cilium:   ~8 Gbps  (BPF map O(1) lookup)

Policy update time (10k policy changes):
  Calico:   ~30-60 seconds
  Cilium:   ~200ms
```

---

## So sánh: Operations & Maturity

| Dimension | Flannel | Calico | Cilium |
| :--- | :--- | :--- | :--- |
| **Maturity** | ★★★★★ | ★★★★★ | ★★★★☆ |
| **Community** | Large | Large | Fast-growing |
| **CNCF status** | Sandbox | Graduated | Graduated |
| **Learning curve** | Low | Medium | High |
| **Troubleshooting** | Hard (no tooling) | Medium | Easy (Hubble) |
| **Production usage** | Widespread | Widespread | Growing rapidly |
| **Managed K8s** | All | All | EKS, GKE, AKS |

---

## So sánh: Resource Overhead

```
Resource consumption per node (approximate):

Flannel:
  Memory: ~30MB (flanneld daemon)
  CPU: ~0.05 core
  iptables: không có (no policy)

Calico:
  Memory: ~100MB (Felix + BIRD)
  CPU: ~0.1-0.2 core
  iptables: grows with policy count (O(n) scan)

Cilium:
  Memory: ~200MB (cilium-agent + BPF programs)
  CPU: ~0.1-0.3 core
  BPF maps: constant size (không grows với policy)

Trade-off:
  Cilium: Higher initial overhead
  Cilium: Better efficiency at scale (>500 policies)
  Calico: Lower overhead, worse performance at scale
```

---

## Khi nào từng CNI win

```
Flannel wins:
  ✅ Simple homelab / learning environment
  ✅ Không cần NetworkPolicy
  ✅ Minimal resource nodes (edge/IoT)
  ✅ Pure overlay, heterogeneous network

Calico wins:
  ✅ BGP integration với on-prem routers (BIRD)
  ✅ Hybrid cloud (bare-metal + VMs)
  ✅ Team đã có Calico expertise
  ✅ Conservative org (more mature, stable)
  ✅ Budget constraint (lighter than Cilium)

Cilium wins:
  ✅ L7 HTTP/gRPC/DNS policy required
  ✅ DNS egress control (toFQDNs)
  ✅ Observability first (Hubble must-have)
  ✅ Large cluster (>500 nodes, >10k policies)
  ✅ Performance-critical (sockops bypass)
  ✅ Zero-trust network architecture
```

---

## Tổng kết: 1 bảng cho mọi quyết định

```
                 Simplicity  Security  Performance  Observability

Flannel             ★★★★★      ★☆☆☆☆      ★★★☆☆        ★☆☆☆☆
Calico              ★★★☆☆      ★★★★☆      ★★★★☆        ★★★☆☆
Cilium              ★★☆☆☆      ★★★★★      ★★★★★        ★★★★★

→ Flannel: Quick wins, no security requirements
→ Calico: Balanced, battle-tested, BGP-ready
→ Cilium: Maximum capability, higher complexity

2026 trend: Cilium adoption accelerating
  GKE, EKS, AKS: all support Cilium natively
  Service mesh partially replaced by Cilium Mesh
  New projects: default to Cilium
```

> **Tập tiếp theo (Tập 42):** Decision Framework — Khi nào dùng Flannel, Calico, Cilium trong Production?
