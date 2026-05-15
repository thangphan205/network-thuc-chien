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

# Tập 6
## Flannel là gì? Vấn đề Pod-to-Pod Communication mà nó giải quyết

**Phần 1 — Flannel** · `#flannel` `#CNI` `#overlay` `#flat-network`

---

## Mục tiêu tập này

- Giải thích bài toán Pod-to-Pod cross-node communication
- Quan sát trạng thái cluster trước và sau khi cài Flannel
- Hiểu khái niệm "flat network" và overlay network
- Thực hành ping cross-node Pod sau khi cài Flannel

**Prerequisites:** Cluster Ubuntu 26.04 (3 nodes) chưa có CNI

---

## Bài toán: 2 Pod, 2 Node, không nói chuyện được

```
Node 1 (192.168.64.10)         Node 2 (192.168.64.11)
┌───────────────────────┐      ┌───────────────────────┐
│ Pod A: 10.244.1.5/24  │      │ Pod B: 10.244.2.7/24  │
│ Default route:         │      │                       │
│  via 10.244.1.1 (cni0)│      │                       │
└───────────────────────┘      └───────────────────────┘

Pod A gửi packet đến 10.244.2.7:
  ip route show → không có route đến 10.244.2.0/24
  → packet bị DROP tại Node 1 (no route to host)
```

**Giải pháp Flannel:** tạo virtual network phẳng — mọi Pod thấy nhau dù ở Node nào.

---

## Flannel tạo "flat network" như thế nào?

**VXLAN mode (mặc định):**
```
Pod A (10.244.1.5) → cni0 → flannel.1 → [VXLAN encap]
                                              ↓ UDP 8472
                                         Node 2 eth0
                                              ↓ [VXLAN decap]
                                         flannel.1 → cni0 → Pod B (10.244.2.7)
```

**host-gw mode (tốc độ cao):**
```
Pod A (10.244.1.5) → cni0 → eth0 → [direct routing] → eth0 → cni0 → Pod B
Node 1 routing table: 10.244.2.0/24 via 192.168.64.11 dev eth0
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Thực hành với Flannel CNI (VXLAN Mode)

Chúng ta sẽ thực hành các bước sau trong phần Lab:

1. **Quan sát Cluster trắng:** Xem xét trạng thái bế tắc của các Node khi chưa được cài đặt mạng.
2. **Cài đặt Flannel:** Triển khai CNI Flannel và quan sát các card mạng ảo `flannel.1` xuất hiện cùng các luật định tuyến mới.
3. **Kiểm chứng Cross-Node:** Tạo các Pod trên những Worker Node khác nhau và xác minh khả năng giao tiếp xuyên Node thành công nhờ VXLAN tunnel.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

**Flannel giải quyết:**
```
Trước Flannel: 10.244.1.5 → 10.244.2.7 = FAILED (no route)
Sau Flannel:   10.244.1.5 → 10.244.2.7 = OK (VXLAN tunnel)
```

**Những gì Flannel tạo ra:**
- `flannel.1` — VXLAN tunnel endpoint (VTEP) trên mỗi Node
- `cni0` — Linux bridge, gateway cho Pods trên Node
- Routes: `10.244.X.0/24 via flannel.1` cho mỗi Node khác

**Flannel KHÔNG làm:**
- Không có NetworkPolicy (bất kỳ Pod nào cũng ping được Pod khác)
- Không có BGP
- Không có L7 policy
- Không có observability

> **Tập tiếp theo:** flanneld làm gì bên trong? Subnet assignment từ etcd hoạt động ra sao?
