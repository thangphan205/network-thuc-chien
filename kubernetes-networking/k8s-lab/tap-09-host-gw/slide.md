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

# Tập 9
## host-gw Mode: Bỏ VXLAN, routing thẳng, tăng tốc 10-15%

**Phần 1 — Flannel** · `#host-gw` `#routing` `#performance` `#L2` `#no-encap`

---

## Mục tiêu tập này

- Hiểu điều kiện bắt buộc để dùng host-gw (cùng L2 segment)
- Switch Flannel từ VXLAN sang host-gw mode
- Quan sát sự biến mất của `flannel.1` và thay đổi routing table
- Đo throughput bằng `iperf3` để so sánh hai mode

**Prerequisites:** Cluster từ Tập 8 với Flannel VXLAN đang chạy

---

## host-gw: Routing thay vì Encapsulation

**VXLAN mode (Tập 8):**
```
Pod A → cni0 → flannel.1 → [UDP 8472 wrap] → eth0 → [unwrap] → flannel.1 → cni0 → Pod B
         └── CPU encode ──────── overhead ──────────── CPU decode ──┘
```

**host-gw mode:**
```
Pod A → cni0 → eth0 → [direct L2 forward] → eth0 → cni0 → Pod B
                No encoding, no decoding — MTU đầy đủ 1500 bytes
```

**Cách hoạt động (flanneld cài routes):**
```
Routing table trên worker1:
  10.244.0.0/24 via 192.168.64.10 dev eth0  ← "controlplane là gateway"
  10.244.1.0/24 dev cni0                    ← local subnet
  10.244.2.0/24 via 192.168.64.12 dev eth0  ← "worker2 là gateway"

Không cần tunnel! Packet đi thẳng — Node = Router.
```

---

## Điều kiện bắt buộc cho host-gw

```
Yêu cầu: Tất cả Nodes phải cùng L2 segment (cùng broadcast domain)

✅ OK: On-premise, tất cả Nodes cùng switch
  worker1 (192.168.64.11) ──┐
  worker2 (192.168.64.12) ──┤── L2 Switch
  controlplane (192.168.64.10)─┘
  → Packet từ worker1 đến worker2 chỉ qua L2, không qua router

❌ FAIL: Cloud VMs ở nhiều subnet/AZ
  worker1 (10.0.1.10 / us-east-1a) ──[Router]── worker2 (10.0.2.10 / us-east-1b)
  → Router không biết route đến 10.244.x.x → DROP

❌ FAIL: Nodes qua nhiều hop router (datacenter khác nhau)
```

**Multipass lab:** Tất cả VMs cùng network `192.168.64.0/24` → host-gw hoạt động!

---

<!-- _class: lab -->

## 🔬 Lab Time: Switch sang host-gw và Benchmark

Chúng ta sẽ thực hành:

1. **Switch mode:** Sửa ConfigMap và restart flanneld để chuyển VXLAN → host-gw.
2. **Quan sát thay đổi:** `flannel.1` biến mất, routes thay đổi, MTU tăng lên 1500.
3. **Verify bằng tcpdump:** Không còn UDP 8472 — packet đi thẳng.
4. **Benchmark:** Dùng `iperf3` đo throughput và latency hai mode.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## So sánh tổng kết VXLAN vs host-gw

| Tiêu chí | VXLAN | host-gw |
| :--- | :--- | :--- |
| Encapsulation overhead | 50 bytes | **0 bytes** |
| MTU cho payload | 1450 bytes | **1500 bytes** |
| Yêu cầu topology | Bất kỳ | **Phải cùng L2** |
| CPU overhead | Encode + Decode | **Không** |
| Latency (approx) | ~0.6 ms | **~0.4 ms (~35% giảm)** |
| Throughput | Baseline | **+10-15%** |
| Cloud compatibility | ✅ | ❌ (thường) |
| Dùng khi | Cloud, multi-subnet | **On-prem, same rack** |

> **Tập tiếp theo:** Giới hạn lớn nhất của Flannel — tại sao không có NetworkPolicy và blast radius khi 1 Pod bị compromise.
