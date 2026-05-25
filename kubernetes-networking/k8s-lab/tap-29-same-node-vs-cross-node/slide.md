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

# Tập 29
## Cùng Node vs Khác Node: Tại sao sockops bypass hoàn toàn XDP/TC?

**Phần 3 — Cilium** · `#sockops` `#same-node` `#bypass` `#packet-flow` `#cilium`

---

## Mục tiêu tập này

- Trace packet path chi tiết: cùng node vs khác node
- Tại sao sockops KHÔNG thể dùng cross-node
- Cilium detect "cùng node" như thế nào (cilium_lxc map)
- Lab đo latency để thấy sự khác biệt thực tế bằng số

**Prerequisites:** Cilium đang chạy với sockops enabled (từ Tập 25)

---

## Same-Node Path — Với sockops bypass

```
Pod A (10.244.1.5) → Pod B (10.244.1.8)  ← CÙNG NODE

Không có sockops (Calico/Flannel):
  App A → write socket → TCP stack → veth0 →
  TC BPF → kernel routing →
  TC BPF → veth1 → TCP stack → read socket → App B
  Latency: ~0.3-0.5ms, CPU: 2x TCP stack

Với sockops (Cilium):
  App A → connect() ← BPF sockops intercept!
    → lookup cilium_lxc: "is 10.244.1.8 on this node?"
    → YES → bpf_msg_redirect_map() redirect
  App A → write socket → BPF redirect → read socket → App B
  Latency: ~0.05ms, CPU: loopback only (6-10x faster!)
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
  TC egress (cil_to_container)
    ↓ policy check ALLOW
  kernel routing
    ↓ VXLAN encapsulation
  eth0 → physical network
                              eth0 → decapsulation
                                ↓
                              TC ingress (cil_from_container)
                                ↓ policy check
                              veth (Pod B)
                                ↓
                              TCP stack → App B
  Latency: ~0.3-0.5ms (network-bound)
```

---

## sockops Detection: cilium_lxc map

```
Khi App A gọi connect(dst_ip=10.244.1.8, dst_port=8080):
  BPF sockops program intercept syscall
  
  1. Lookup dst_ip trong cilium_lxc map:
     bpf_map_lookup_elem(&cilium_lxc, &dst_ip)
  
  2. Nếu FOUND → dst Pod trên cùng node này!
     cilium_lxc chỉ chứa endpoints của NODE HIỆN TẠI
     → redirect: bpf_sock_hash_update() + bpf_msg_redirect_hash()
     → Kernel redirect write/read giữa 2 socket trực tiếp
  
  3. Nếu NOT FOUND → cross-node
     → sockops không làm gì
     → packet đi xuống TCP stack → TC path xử lý

Key insight: cilium_lxc = "local endpoint map"
```

---

## Tại sao sockops KHÔNG dùng được cross-node?

```
sockops hoạt động ở socket layer:
  → Chỉ thấy: src socket ↔ dst socket (in-kernel)
  → Không thể "redirect qua mạng vật lý"

Cross-node PHẢI có:
  - Encapsulation (thêm outer IP header)
  - Routing (gửi đúng Node NIC)
  - Physical Network I/O
  → Tất cả xảy ra DƯỚI socket layer

sockops → socket buffer redirect (in-kernel memory)
TC → packet manipulation + routing (kernel network stack)

sockops cross-node = loopback cho remote connection
→ Impossible by design
```

---

## Kết quả đo thực tế

| Metric | Same-node (sockops) | Cross-node (TC+VXLAN) |
| :--- | :--- | :--- |
| **Latency (RTT)** | ~0.05ms | ~0.35ms |
| **Bandwidth** | ~18 Gbps | ~2 Gbps |
| **CPU overhead** | Minimal | 2x TCP stack + encap |
| **Path** | Socket → redirect → Socket | Socket → veth → TC → NIC → NIC → TC → veth → Socket |

```
Ý nghĩa cho application design:
  Microservices gọi nhau nhiều → schedule cùng node → 6-10x faster
  Cilium topology-aware: pod affinity + sockops = best of both worlds
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Đo latency và trace 2 paths

Chúng ta sẽ thực hành:

1. **Deploy 4 pods:** same-server/client (worker1), cross-server (worker2), cross-client (worker1).
2. **Đo latency:** `ping -c 50` — same-node ~0.05ms vs cross-node ~0.35ms.
3. **Đo bandwidth:** `iperf3` — same-node ~18 Gbps vs cross-node ~2 Gbps.
4. **Verify sockops counter tăng** khi có same-node traffic.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 30):** L3/L4 Policy trong Cilium — So sánh với Kubernetes NetworkPolicy và CiliumNetworkPolicy.
