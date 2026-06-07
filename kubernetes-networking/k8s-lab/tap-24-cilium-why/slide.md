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

# Tập 24
## Tại sao Cilium? Pain points của Calico & sockops bypass

**Phần 3 — Cilium** · `#cilium` `#ebpf` `#sockops` `#calico` `#painpoints`

---

## Mục tiêu tập này

- Hiểu pain points thực sự của Calico ở scale lớn
- Tại sao iptables là bottleneck trong modern cloud-native
- sockops bypass hoạt động ra sao — loại bỏ hoàn toàn iptables
- Cilium như "thế hệ tiếp theo" của CNI

**Prerequisites:** Cluster K8s đang chạy, chuẩn bị cài Cilium thay thế Calico

---

## Pain Point 1: iptables là O(n) nightmare

```
Calico (iptables mode) problem:
─────────────────────────────────
1000 Services  → 10,000+ iptables rules
5000 Pods      → 25,000+ cali-* chains
10,000 Policy  → Memory bloat trên mỗi Node

Mỗi packet phải traverse LINEAR list của rules!
→ Latency tăng khi cluster grow
→ iptables-restore: 30-60 giây cho cluster lớn

Real metric (OpenAI report 2023):
- 5000 nodes, 100k policies
- iptables update: 45 minutes (!!)
- Cilium BPF maps: < 1 giây
```

---

## Pain Point 2: Không có L7 visibility

```
Calico chỉ thấy:
  [Pod A] ──TCP:8080──▶ [Pod B]   ← Layer 4

Cilium thấy:
  [Pod A] ──GET /api/users──▶ [Pod B]   ← Layer 7

Calico không thể:
  ❌ Block HTTP POST đến /admin
  ❌ Rate limit theo HTTP method
  ❌ Log "which API endpoint bị gọi"
  ❌ Retry logic awareness

→ Khi gặp bug "Pod A lỗi 403 từ Pod B":
  Calico: "Policy cho phép TCP:8080" (không biết HTTP gì)
  Cilium: "hubble observe" → thấy ngay HTTP path bị deny
```

---

## Pain Point 3: Observability gaps

```
Debugging với Calico:
  kubectl exec pod -- tcpdump -i eth0 port 8080
  iptables -L cali-tw-<endpoint> -n
  journalctl -u felix | grep "packet drop"
  → Fragmented, manual, slow

Debugging với Cilium:
  hubble observe --namespace production --verdict DROPPED
  → Instant: "10.244.1.5 → 10.244.2.8: Policy denied HTTP POST /admin"

Cilium Hubble = built-in distributed tracing cho network
```

---

## sockops: Kernel shortcut cho same-node traffic

```
Normal path (Calico/Flannel):
  App A → socket → TCP stack → veth → iptables → cali bridge
       → iptables → veth → TCP stack → socket → App B
  
  Total: 2x TCP stack + 2x iptables = ~30-40 microseconds

sockops path (Cilium, same node):
  App A → socket → BPF hook intercept
       → redirect trực tiếp → socket → App B
  
  Total: socket-to-socket direct = ~3-5 microseconds

Gain: 6-10x faster cho same-node Pod-to-Pod!
```

---

## So sánh Calico vs Cilium

| Pain Point | Calico | Cilium |
| :--- | :--- | :--- |
| Rule scale | O(n) iptables | O(1) BPF maps |
| L7 visibility | Không có | Native HTTP/gRPC |
| Observability | Manual tcpdump | Hubble real-time |
| Same-node latency | ~0.3ms | ~0.05ms (sockops) |
| Policy update time | Giây-phút | Milliseconds |

```
Cilium không phải "CNI tốt hơn" — đó là paradigm shift:
iptables (1990s) → eBPF (2016+)
Packet filtering → Programmable kernel
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Cài Cilium và đo latency sockops

Chúng ta sẽ thực hành:

1. **Cài Cilium** qua Helm thay thế CNI cũ.
2. **Verify sockops active:** `cilium status`, `bpftool prog list | grep sock`.
3. **Deploy pods same-node** trên worker1, đo latency với iperf3.
4. **So sánh** bandwidth và latency same-node vs cross-node.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 25):** BPF Maps — Hash, LRU, Array, Per-CPU: Vũ khí hiệu năng của Cilium.
