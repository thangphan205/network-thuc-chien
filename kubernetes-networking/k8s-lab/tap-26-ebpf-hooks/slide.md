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

# Tập 26
## 3 Hook Points của eBPF: XDP, TC và Cgroup/Socket hooks — Mỗi cái làm gì?

**Phần 3 — Cilium** · `#ebpf` `#XDP` `#TC` `#cgroup-socket` `#hookpoints`

---

## Mục tiêu tập này

- Packet journey qua Linux network stack
- 3 điểm hook của eBPF: XDP, TC, Cgroup/Socket hooks
- Mỗi hook phù hợp với use case nào
- Cilium tự động chọn hook nào cho từng scenario

**Prerequisites:** Cilium đang chạy (từ Tập 23)

---

## Linux network stack — Nơi packet đi qua

```
  NIC Hardware
       │
  ┌────▼────┐
  │   XDP   │ ← Hook 1: SỚM NHẤT (trước kernel buffer)
  └────┬────┘
       │ (packet vào kernel)
  ┌────▼────────────┐
  │  Network Stack  │
  │  ┌───────────┐  │
  │  │    TC     │ ◄── Hook 2: Sau NIC driver, có SKB
  │  │ ingress/  │  │
  │  │  egress   │  │
  │  └───────────┘  │
  │  IP routing,    │
  │  conntrack...   │
  └────┬────────────┘
       │
  ┌────▼────┐
  │  Socket │ ← Hook 3: cgroup/socket hooks (connect/sendmsg/recvmsg)
  └─────────┘
       │
    Application
```

---

## Hook 1: XDP — eXpress Data Path

```
Vị trí: Ngay sau NIC driver, TRƯỚC khi allocate SKB
Thời điểm: Packet chưa vào kernel memory buffer

Ưu điểm:
  - NHANH NHẤT: bỏ qua toàn bộ kernel stack
  - Có thể process 10-100M packets/giây per core
  - DROP malicious packet trước khi tốn CPU

Nhược điểm:
  - Không có SKB → không có routing table, conntrack
  - Không thể modify TCP state
  - Limited access to kernel data structures

Cilium dùng XDP cho:
  - DDoS mitigation: drop attack traffic sớm nhất
  - Host-level packet filtering (NodePort acceleration)
  - Kube-proxy replacement (Service load balancing)
```

---

## Hook 2: TC — Traffic Control

```
Vị trí: Sau NIC driver, có SKB (Socket Buffer)
Thời điểm: Packet đã trong kernel, có đầy đủ metadata

TC ingress: packet từ NIC vào kernel
TC egress:  packet từ kernel ra NIC

Ưu điểm:
  - Có SKB → access đầy đủ: src/dst IP, port, conntrack state
  - Có thể modify packet (NAT, encapsulation, redirect)
  - Attach vào bất kỳ interface nào (eth0, veth, tunnel)
  - Vẫn nhanh hơn iptables 3-5x

Cilium dùng TC cho:
  - NetworkPolicy enforcement (L3/L4/L7)
  - Encapsulation (VXLAN/Geneve khi cross-node)
  - NAT (Service → Pod translation)
  - Packet redirect giữa interfaces
```

---

## Hook 3: Cgroup/Socket hooks — Socket LB

> **Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** `sockops` (prog type `sock_ops`/`sk_msg`, TCP socket-splice bypass hoàn toàn network stack) đã bị **loại bỏ từ v1.14**. Cơ chế socket-layer hiện tại dùng prog type **`cgroup_sock_addr`** (hàm `cil_sock4_connect`, `cil_sock4_sendmsg`...), gọi là **Socket LB**.

```
Vị trí: cgroup, hook connect()/sendmsg()/recvmsg() syscall
Thời điểm: Trước khi socket gửi packet đi

Socket LB intercept:
  - connect() syscall → rewrite IP:port đích (ClusterIP/NodePort → backend Pod)
  - sendmsg()/recvmsg() → rewrite tương tự cho UDP

Vai trò:
  - Thay thế kube-proxy hoàn toàn cho service load-balancing
  - Rewrite xảy ra 1 lần tại socket layer, không cần iptables DNAT mỗi packet

Same-node speedup KHÔNG đến từ Socket LB — mà từ cơ chế khác ở tầng TC:
  - BPF Host-Routing (bpf_lxc.c): TC BPF tra map cilium_lxc, nếu đích là
    pod local → bpf_redirect_peer() nhảy thẳng veth peer
  - Vẫn qua veth + TC BPF, chỉ bỏ qua iptables/netfilter (xem Tập 27)

Cilium dùng Socket LB:
  - Mọi Pod-to-Service traffic: rewrite tại connect(), thay kube-proxy NAT
```

---

## Cilium's 3-layer hook strategy

| Hook | Vị trí | Speed | Use case chính |
| :--- | :--- | :--- | :--- |
| **XDP** | Trước SKB | ★★★★★ | DDoS drop, NodePort LB |
| **TC** | Có SKB | ★★★★☆ | Policy, NAT, encap, BPF host-routing |
| **Cgroup/Socket** | Socket layer | ★★★★★ | Socket LB — service rewrite tại connect() |

```
Cilium tự động chọn đường tối ưu:
  Mọi Pod-to-Service? → Socket LB path (connect()-time rewrite)
  Same node (sau rewrite)? → TC path + BPF host-routing (bpf_redirect_peer, nhanh nhất)
  Cross node?    → TC path (full feature set, qua VXLAN nếu cần)
  NodePort/DDoS? → XDP path (maximum throughput)

Không cần config thủ công:
  cilium-agent tự detect topology → attach đúng BPF program
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Xem BPF programs tại từng hook point

Chúng ta sẽ thực hành:

1. **List programs theo type:** `bpftool prog list | grep -E "name|type"` — thấy `sched_cls` (TC), `cgroup_sock_addr` (Socket LB), `xdp`.
2. **Xem TC programs trên veth:** `tc qdisc show` và `tc filter show dev veth ingress/egress`.
3. **Verify hook points:** Thấy `cil_from_container` (TC ingress) và `cil_to_container` (TC egress) gắn trên từng Pod veth.
4. **Demo hoạt động của TC:** Bắt packet qua veth và xem BPF program process.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 27):** Cùng Node vs Khác Node — Trace packet path chi tiết và đo latency thực tế.
