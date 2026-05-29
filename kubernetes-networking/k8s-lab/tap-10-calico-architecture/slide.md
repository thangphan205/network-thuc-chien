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

# Tập 10 - Calico - Architecture
## Kiến trúc Calico: Felix, BIRD, Typha — Ai làm gì?

**Phần 2 — Calico** · `#calico` `#felix` `#BIRD` `#typha` `#architecture`

![height:200px](https://www.tigera.io/app/uploads/2026/01/Calico-logo-2026-white-text.svg)

---

## Mục tiêu tập này

- Hiểu vai trò chính xác của **Felix**, **BIRD**, **Typha** trong kiến trúc Calico.
- Trace luồng từ `NetworkPolicy` YAML → iptables rule trên Node.
- Quan sát Felix log khi policy thay đổi — event-driven trong ms.
- Dùng `calicoctl` để debug workload endpoints, IP pools, BGP status.

**Prerequisites:** Cluster từ Tập 9 với Calico đang chạy.

---

## Luồng dữ liệu trong Calico

```
NetworkPolicy (YAML)
        │
        ▼
  K8s API Server
        │  watch
        ▼
  Typha (nếu cluster lớn)   ← cache, fan-out tới nhiều Felix
        │
        ▼
  Felix (mỗi Node)          ← dịch policy → rules
        │
        ├── iptables chains  (cali-FORWARD, cali-fw-*, cali-tw-*)
        └── eBPF maps        (nếu dùng eBPF dataplane)

  BIRD (mỗi Node)           ← quảng bá Pod subnet qua BGP
        │
        └── Kernel routing table
```

---

## Felix: Policy Engine trên từng Node

Felix chạy như DaemonSet — 1 instance mỗi Node, luôn watch K8s API:

- Nhận event `NetworkPolicy` / `Pod` / `Node` thay đổi → tính toán lại rules.
- Dịch policy thành **iptables chains** (hoặc eBPF programs) và cập nhật atomic.
- Toàn bộ quá trình: event nhận → iptables update **< 100ms**.
- Không cần restart Pod, Node, hay DaemonSet.

**Chain hierarchy Felix tạo:**
- `FORWARD → cali-FORWARD → cali-from-wl-dispatch → cali-fw-<id>` (egress)
- `cali-to-wl-dispatch → cali-tw-<id>` (ingress)

> Mỗi lần apply `NetworkPolicy`, Felix tự đồng bộ — không có hành động thủ công nào cần thiết.

---

## BIRD & Typha

**BIRD** — BGP daemon, chạy cùng Felix trong Pod `calico-node`:
- Peer với BIRD của tất cả Nodes khác (full mesh) hoặc Route Reflector.
- Quảng bá: *"Pod subnet `10.244.1.0/24` nằm ở Node này"*.
- Cài routes nhận được vào kernel routing table.
- Dùng khi chạy BGP mode (không overlay). Với VXLAN: vẫn chạy nhưng không cần thiết.

**Typha** — cache layer tùy chọn:
- Đứng giữa K8s API Server và tất cả Felix instances.
- Mỗi Felix chỉ kết nối đến Typha thay vì trực tiếp API Server.
- **Tigera Operator tự bật Typha khi node count > 3** (tùy version).
- Cluster nhỏ (≤ 3 nodes): không cần — Felix kết nối thẳng API Server.

---

<!-- _class: lab -->

## 🔬 Lab Time: Giải phẫu Calico Architecture

Thực hành theo thứ tự trong `lab-guide.md`:

1. **TN1 — Felix log real-time:** mở 2 terminal song song — terminal 1 watch Felix log, terminal 2 apply NetworkPolicy mới → thấy Felix xử lý update trong ms.
2. **TN2 — iptables chains:** liệt kê `cali-*` chains, xem `cali-FORWARD`, drill vào `cali-tw-<hash>` để thấy ACCEPT/DROP rule tương ứng với policy.
3. **TN3 — calicoctl:** cài binary, dùng `get workloadendpoint`, `get ippool`, `get felixconfig`, `node status`.
4. **TN4 — Typha:** kiểm tra Typha có chạy không, đếm Felix connections, xem Operator quyết định bật Typha khi nào.

👉 **Làm theo `lab-guide.md`**

---

## Key Takeaways

- **Felix** là trái tim: event-driven, dịch NetworkPolicy → iptables/eBPF < 100ms, không polling.
- **BIRD** quảng bá Pod routes qua BGP — cần thiết khi chạy BGP mode, không quan trọng với VXLAN.
- **Typha** chỉ cần khi cluster lớn (> 50 nodes) để giảm tải K8s API Server.
- **calicoctl** là `kubectl` cho Calico objects — dùng để debug endpoint, IP pool, BGP session.

```bash
kubectl -n calico-system logs daemonset/calico-node -c calico-node  # Felix logs
calicoctl get workloadendpoint        # Pods được Calico quản lý
calicoctl node status                 # BGP peers + health
```

> **Tập tiếp theo:** iptables vs eBPF dataplane — khi nào upgrade và đánh đổi là gì?
