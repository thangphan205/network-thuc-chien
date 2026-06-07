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

# Tập 16
## BGP trong Calico: Node-to-Node Mesh và chuyển từ VXLAN

**Phần 2 — Calico** · `#BGP` `#AS` `#BIRD` `#routing` `#no-encapsulation`

---

## Mục tiêu tập này

- Hiểu khi nào dùng BGP thay vì VXLAN/IPIP
- Cấu hình Calico sang BGP mode (không encapsulation)
- Dùng `calicoctl node status` để xem BGP session
- Verify: routing table thay đổi, tcpdump không còn VXLAN
- Troubleshoot 5 kịch bản BGP lỗi thường gặp trên môi trường thực

**Prerequisites:** Cluster Calico từ Tập 9-12 với VXLAN (sẽ chuyển sang BGP)

---

## BGP: Border Gateway Protocol

**Mỗi Node chạy BIRD daemon, quảng bá Pod CIDR của mình qua BGP sessions:**

```
Production — eBGP với ToR Switch:          Lab này — Node-to-Node Mesh (iBGP):

ToR Switch (AS 65000)                      controlplane (AS 64512)
    │                                           │
    ├── Node 1 (AS 64512)                  ────┼──── worker1 (AS 64512)
    │   Quảng bá: 10.244.1.0/26 ở đây         │     BGP session trực tiếp
    ├── Node 2 (AS 64512)                  ────┘──── worker2 (AS 64512)
    └── Node 3 (AS 64512)                        Full Mesh: n*(n-1)/2 sessions
```

**Lợi ích chung:**
- Không có encapsulation overhead (không VXLAN, không IPIP)
- Routes inject vào kernel với `proto bird` → forward thẳng qua `eth0`

---

## Hai topology BGP trong Calico

| | Node-to-Node Mesh | External BGP (với ToR) |
| :--- | :--- | :--- |
| **BGP type** | iBGP (cùng AS 64512) | eBGP (khác AS) |
| **Peer** | Mọi node peer với nhau | Mỗi node peer với ToR switch |
| **Scale** | n*(n-1)/2 sessions | n sessions (1 per node) |
| **Yêu cầu** | L2 flat network giữa nodes | L3 fabric + router hỗ trợ BGP |
| **Lab này** | ✅ | ❌ (Tập 17+) |

> **Lab này dùng Node-to-Node Mesh trên L2 flat network (Multipass).**
> Không cần ToR switch thật — BIRD trên mỗi node peer trực tiếp với nhau.

---

## Các chế độ mạng của Calico

| Chế độ | Encapsulation | Yêu cầu | Dùng khi |
| :--- | :--- | :--- | :--- |
| **VXLAN** | Full VXLAN | Bất kỳ topology | Cloud, multi-subnet |
| **IPIP** | IP-in-IP tunnel | L3 routed fabric | Datacenter |
| **BGP (direct)** | Không có | **L2 flat** (node mesh) hoặc L3 + BGP router | On-prem, performance |
| **VXLANCrossSubnet** | VXLAN chỉ khi cross-subnet | Mixed | Datacenter hybrid |

> **Điều kiện bắt buộc cho BGP direct:** tất cả nodes cùng L2 subnet.
> Nếu cross-subnet, packet bị router trung gian drop vì không biết route đến Pod CIDR.

---

## Khi nào dùng BGP

```
✅ On-premise datacenter với L3 fabric
✅ Cần server bare-metal access Pod IPs trực tiếp
✅ Performance-sensitive workloads
✅ Team đã quen BGP

❌ Cloud VPC (VPC routing không support custom pod CIDR)
❌ Simple cluster không cần routing integration
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Chuyển sang BGP mode và Verify

Chúng ta sẽ thực hành:

1. **Kiểm tra hệ thống:** Đảm bảo Nodes, Pods và Calico hoạt động bình thường.
2. **Switch sang BGP:** Patch IP Pool `encapsulation: None`.
3. **Quan sát routing table:** Routes dùng `eth0` thay vì `vxlan.calico`, inject bởi BIRD.
4. **Xem BGP sessions:** `calicoctl node status` — verify `Established`.
5. **Test routing:** Tcpdump confirm không còn UDP 8472, ICMP đi thẳng.
6. **Troubleshoot:** 5 kịch bản lỗi thực tế — tạo lỗi → điều tra → fix.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## 🔧 Troubleshooting BGP — Tóm tắt

| Triệu chứng | Công cụ điều tra | Nguyên nhân phổ biến |
| :--- | :--- | :--- |
| BGP state `Active` | `nc -zv <peer> 179` | TCP 179 bị block (iptables) |
| BGP state `Idle` | `kubectl logs calico-node` | Felix chưa start |
| `proto bird` routes trống | `watch ip route show proto bird` | Felix chưa apply (đợi 30s) |
| Pod ping 100% loss, routes OK | `iptables -L FORWARD -n -v` | FORWARD chain DROP |
| `No process is using this socket` | `kubectl get pod -n kube-system` | calico-node pod restarting |
| `vxlan.calico` vẫn UP | `ip route show \| grep vxlan` | Transient — OK nếu routes dùng eth0 |

**Quy tắc debug:** Control plane OK (BGP up, routes có) → vấn đề ở dataplane (iptables). Routes trống → vấn đề ở Felix/BIRD.

---

## Bài toán Scale: Full Mesh BGP

**Full mesh = mỗi node peer với mọi node khác:**

```
n = số nodes    Số sessions = n × (n-1) / 2

3 nodes:    3 sessions    ✅  (lab hiện tại)
10 nodes:  45 sessions    ✅
50 nodes: 1225 sessions   ⚠️
100 nodes: 4950 sessions  ❌  mỗi node duy trì 99 TCP connections
500 nodes: 124750 sessions ❌❌
```

**Triệu chứng khi quá tải:** CPU spike trên calico-node, BGP convergence chậm, node mới join mất nhiều thời gian thiết lập sessions.

---

## Route Reflector: Giải pháp iBGP Scaling

**Thay vì peer full mesh, mỗi node chỉ peer với Route Reflector (RR):**

```
Full Mesh (6 nodes = 15 sessions):    Route Reflector (6 nodes = 6 sessions):

N1 ─── N2                             N1 ──┐
│ ╲   ╱ │                             N2 ──┤
│  N3   │          →                  N3 ──┼──► RR (controlplane)
│  │    │                             N4 ──┤
N4 ─── N5                             N5 ──┘
     N6
```

**Cách RR hoạt động:** RR nhận route từ client → reflect đến tất cả clients khác. NEXT_HOP giữ nguyên IP node gốc → packet forward trực tiếp node-to-node, không qua RR.

**Trade-off:** RR = single point of failure → production cần ≥ 2 RR nodes.

> Cấu hình thực hành RR có trong **Tập 17 (tài liệu tham khảo)**.

---

> **Tập tiếp theo:** WireGuard trong Calico — mã hóa traffic nội bộ giữa các nodes và bẫy MTU 1440 bytes.
