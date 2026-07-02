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

# Tập 25
## Kiến trúc Cilium: Operator, Agent, GoBGP, Hubble — So sánh với Calico

**Phần 3 — Cilium** · `#cilium` `#architecture` `#operator` `#gobgp` `#hubble`

---

## Mục tiêu tập này

- Map kiến trúc Cilium: mỗi component làm gì
- So sánh với Calico (Felix ↔ Agent, BIRD ↔ GoBGP)
- Cilium Operator vs Tigera Operator — khác biệt vai trò
- Cilium Identity model: tại sao dùng label hash thay vì IP

**Prerequisites:** Cilium đang chạy (từ Tập 23)

---

## Kiến trúc tổng quan

```
┌─────────────────────────────────────────────────────────┐
│                    K8s Control Plane                    │
│  API Server ──── etcd                                   │
└──────────────┬──────────────────────────────────────────┘
               │ watch
    ┌──────────▼──────────┐
    │   Cilium Operator   │  ← 1 instance per cluster
    │  (CRD management,   │    (vs Tigera Operator)
    │   IPAM allocation)  │
    └──────────┬──────────┘
               │ coordinates
    ┌──────────▼──────────────────────────────────┐
    │            Cilium Agent (DaemonSet)         │
    │  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
    │  │  Policy  │  │  GoBGP   │  │  Hubble  │  │
    │  │  Engine  │  │(optional)│  │  Server  │  │
    │  └────┬─────┘  └──────────┘  └──────────┘  │
    │       │ write BPF Maps                      │
    │  ┌────▼─────────────────────────────────┐   │
    │  │  BPF Programs (XDP, TC, cgroup/socket)│   │
    └──└──────────────────────────────────────┘───┘
```

---

## Cilium Agent — Tất cả trong một

```
cilium-agent (chạy trên mỗi Node):
  ├── Policy Manager
  │     Watch NetworkPolicy + CiliumNetworkPolicy từ API server
  │     Compile policy → BPF Map entries
  │
  ├── Endpoint Manager
  │     Track tất cả Pod trên node
  │     Assign identity (numeric ID, không phải IP!)
  │
  ├── IPAM Controller
  │     Allocate Pod IP (coordinate với Operator)
  │
  ├── GoBGP (optional)
  │     BGP speaker thay thế BIRD
  │     BGP peering với ToR switch
  │
  └── Hubble Observer
        Record network events vào ring buffer
        Serve gRPC API cho hubble-relay
```

---

## Calico vs Cilium: Component mapping

| Calico | Cilium | Khác biệt |
| :--- | :--- | :--- |
| **Felix** | **cilium-agent** | Cilium agent all-in-one (IPAM + BGP + observe) |
| **BIRD** | **GoBGP (built-in)** | GoBGP là Go library, không phải process riêng |
| **Typha** | **Cilium Operator** | Operator focus CRD management + IPAM allocation |
| **calicoctl** | **cilium CLI** | Cilium CLI tích hợp Hubble commands |
| **Calico datastore** | **K8s CRDs** | Cilium không cần etcd riêng |
| *(không có)* | **Hubble** | Built-in distributed network observability |

---

## Cilium Identity: Label hash thay vì IP

```
Calico model:
  Policy: "allow src_ip=10.244.1.5 → dst_port=8080"
  Vấn đề: Pod restart → IP thay đổi → policy "miss"
           Phải wait Felix converge lại

Cilium model:
  Identity = hash(Pod labels) = số nguyên (ví dụ: 7891)
  Policy: "allow identity=7891 → dst_port=8080"
  
  Pod labels: {app=frontend, env=prod}
  → Identity: deterministic hash → 7891

  Pod restart → IP mới NHƯNG labels không đổi
  → Identity 7891 vẫn giữ nguyên
  → Policy tự động apply cho Pod mới!

Lợi ích: Zero-downtime rolling update không break policy
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Khám phá Cilium Architecture

Chúng ta sẽ thực hành:

1. **Xem components:** `cilium status`, danh sách Operator + Agent + Hubble pods.
2. **Inspect endpoints:** `cilium endpoint list` — thấy identity từng Pod.
3. **Xem identities:** `cilium identity list` — label → numeric ID mapping.
4. **Verify identity persist** khi Pod restart — labels → identity không đổi.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 26):** 3 Hook Points của eBPF — XDP, TC và Cgroup/Socket hooks làm gì khác nhau?
