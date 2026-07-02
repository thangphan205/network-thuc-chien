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

# Tập 27
## Cùng Node vs Khác Node: BPF Host-Routing tăng tốc same-node ra sao?

**Phần 3 — Cilium** · `#bpf-host-routing` `#same-node` `#packet-flow` `#cilium`

> **Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** tính năng `sockops` (TCP socket-splice bypass hoàn toàn network stack) đã bị **loại bỏ từ v1.14**. Cơ chế same-node speedup thật sự là **BPF Host-Routing** (`bpf_redirect_peer()`/`bpf_redirect_neigh()` ở tầng TC) — vẫn qua veth + TC BPF, chỉ bỏ qua iptables/netfilter.

---

## Mục tiêu tập này

- Trace packet path chi tiết: cùng node vs khác node
- Tại sao BPF Host-Routing KHÔNG thể dùng cross-node
- Cilium detect "cùng node" như thế nào (cilium_lxc map)
- Lab đo latency để thấy sự khác biệt thực tế bằng số

**Prerequisites:** Cilium đang chạy với BPF Host-Routing (mặc định từ v1.9+, từ Tập 23)

---

## Same-Node Path — Với BPF Host-Routing

```
Pod A (10.244.1.5) → Pod B (10.244.1.8)  ← CÙNG NODE

Không có BPF Host-Routing (Calico/Flannel, dùng iptables):
  App A → write socket → TCP stack → veth0 →
  iptables (nhiều chain) → kernel routing →
  iptables → veth1 → TCP stack → read socket → App B
  Latency: ~0.3-0.5ms, CPU: 2x TCP stack + iptables traversal

Với BPF Host-Routing (Cilium):
  App A → write socket → TCP stack → veth0 (TC BPF: cil_from_container)
    → lookup cilium_lxc: "is 10.244.1.8 on this node?"
    → YES → bpf_redirect_peer() nhảy thẳng sang veth1 (TC BPF: cil_to_container)
  → TCP stack → read socket → App B
  (Vẫn qua veth + TC BPF cả 2 đầu — chỉ bỏ qua iptables/netfilter)
  Latency: ~0.05ms, CPU: thấp hơn nhiều (6-10x faster!)
```

---

## Cross-Node Path — TC path

```
Pod A (10.244.1.5, Node1) → Pod B (10.244.2.8, Node2)

  [Node 1]                    [Node 2]
  App A
    ↓ write socket
  TCP stack
    ↓
  veth (Pod A)
    ↓
  TC ingress (cil_from_container) ← packet RA khỏi Pod A
    ↓ policy check ALLOW
  kernel routing
    ↓ VXLAN encapsulation
  eth0 → physical network
                              eth0 → decapsulation
                                ↓
                              TC egress (cil_to_container) ← packet VÀO Pod B
                                ↓ policy check
                              veth (Pod B)
                                ↓
                              TCP stack → App B
  Latency: ~0.3-0.5ms (network-bound)
```

---

## BPF Host-Routing Detection: cilium_lxc map

```
Khi packet từ Pod A đi tới TC ingress hook (cil_from_container):
  TC BPF program (bpf_lxc.c) chạy trên veth của Pod A

  1. Lookup dst_ip trong cilium_lxc map:
     bpf_map_lookup_elem(&cilium_lxc, &dst_ip)

  2. Nếu FOUND → dst Pod trên cùng node này!
     cilium_lxc chỉ chứa endpoints của NODE HIỆN TẠI (id/ifindex/mac)
     → gọi bpf_redirect_peer()/bpf_redirect_neigh() với ifindex lấy từ map
     → Nhảy thẳng sang veth peer của Pod B, vẫn qua TC BPF (cil_to_container)

  3. Nếu NOT FOUND → cross-node
     → không redirect được (không biết ifindex đích)
     → packet đi tiếp qua routing table bình thường → VXLAN → NIC

Key insight: cilium_lxc = "local endpoint map" (id/ifindex/mac của Pod local)
```

---

## Tại sao BPF Host-Routing KHÔNG dùng được cross-node?

```
bpf_redirect_peer()/bpf_redirect_neigh() cần biết chính xác ifindex
của veth đích để nhảy thẳng tới đó — thông tin này chỉ có trong
cilium_lxc cho Pod chạy LOCAL trên cùng node.

Cross-node PHẢI có:
  - Encapsulation (thêm outer IP header — VXLAN/Geneve)
  - Routing (gửi đúng Node qua NIC vật lý)
  - Physical Network I/O
  → Không có "ifindex" nào để redirect trực tiếp tới node khác

TC + BPF host-routing → redirect trực tiếp trong node (biết ifindex đích)
TC + routing thường   → encap + gửi qua NIC (không biết ifindex đích ở xa)

BPF Host-Routing cross-node = không có đích cụ thể để redirect tới
→ Buộc phải đi qua path encapsulation/routing đầy đủ
```

---

## Kết quả đo thực tế

| Metric | Same-node (BPF Host-Routing) | Cross-node (TC+VXLAN) |
| :--- | :--- | :--- |
| **Latency (RTT)** | ~0.05ms | ~0.35ms |
| **Bandwidth** | ~18 Gbps | ~2 Gbps |
| **CPU overhead** | Thấp (bỏ iptables/netfilter) | 2x TCP stack + iptables + encap |
| **Path** | Socket → veth → TC (redirect_peer) → veth → Socket | Socket → veth → TC → NIC → NIC → TC → veth → Socket |

```
Ý nghĩa cho application design:
  Microservices gọi nhau nhiều → schedule cùng node → 6-10x faster
  Cilium topology-aware: pod affinity + BPF host-routing = best of both worlds
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Đo latency và trace 2 paths

Chúng ta sẽ thực hành:

1. **Deploy 4 pods:** same-server/client (worker1), cross-server (worker2), cross-client (worker1).
2. **Đo latency:** `ping -c 50` — same-node ~0.05ms vs cross-node ~0.35ms.
3. **Đo bandwidth:** `iperf3` — same-node ~18 Gbps vs cross-node ~2 Gbps.
4. **Verify BPF Host-Routing active:** `cilium status --verbose | grep Routing:` → `Host: BPF`.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 28):** L3/L4 Policy trong Cilium — So sánh với Kubernetes NetworkPolicy và CiliumNetworkPolicy.
