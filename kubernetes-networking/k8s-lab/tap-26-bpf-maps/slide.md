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
## BPF Maps: Hash, LRU, Array, Per-CPU — Vũ khí hiệu năng của Cilium

**Phần 3 — Cilium** · `#ebpf` `#bpfmaps` `#kernel` `#hashmap` `#performance`

---

## Mục tiêu tập này

- BPF Maps là gì — cầu nối giữa kernel space và user space
- 4 loại Map quan trọng nhất trong Cilium
- Tại sao BPF Maps thay thế được iptables chains
- Inspect BPF Maps thực tế để hiểu Cilium đang "nghĩ" gì

**Prerequisites:** Cilium đang chạy trên cluster (từ Tập 25)

---

## BPF Maps là gì?

```
BPF Maps = Shared memory giữa:
  ┌─────────────────┐         ┌─────────────────┐
  │   BPF Program   │ ◄─────► │  User Space     │
  │  (kernel space) │ read/   │  (cilium-agent) │
  │                 │ write   │                 │
  └─────────────────┘         └─────────────────┘

Ví dụ thực tế:
  cilium-agent ghi policy vào BPF Map
  → BPF program trong kernel đọc Map per-packet
  → Quyết định ALLOW/DROP trong nanoseconds

Không cần syscall! Không cần context switch!
→ Đây là bí mật của Cilium performance
```

---

## 4 loại Map quan trọng

| Type | Use case | Đặc điểm |
| :--- | :--- | :--- |
| **BPF_MAP_TYPE_HASH** | Policy lookup: IP → rule | O(1) lookup, collision resistant |
| **BPF_MAP_TYPE_LRU_HASH** | Conntrack: flow state | Auto-evict oldest entry, fixed size |
| **BPF_MAP_TYPE_ARRAY** | Config, metrics counters | Index-based, always allocated |
| **BPF_MAP_TYPE_PERCPU_HASH** | Per-CPU packet counters | No lock contention, sum when read |

---

## Hash Map: Policy Lookup O(1)

```
cilium_policy_<endpoint_id> (BPF_MAP_TYPE_HASH)
─────────────────────────────────────────────────
Key: {src_ip, dst_ip, dst_port, protocol}
Value: {verdict: ALLOW/DROP, action_flags}

Lookup: O(1) — một hash function, một memory read
vs iptables: traverse n rules linearly

Khi packet đến:
  1. BPF program extract 5-tuple từ packet header
  2. bpf_map_lookup_elem(&cilium_policy, &key)
  3. Return ALLOW → forward
     Return NULL  → DROP (default deny)

Với 100,000 policies: vẫn O(1)!
```

---

## LRU Hash Map: Conntrack không cần lock

```
cilium_ct_tcp4 (BPF_MAP_TYPE_LRU_HASH)
───────────────────────────────────────
Key: {src_ip, src_port, dst_ip, dst_port, proto}
Value: {state, last_seen, flags, rev_nat_index}

LRU = Least Recently Used eviction:
  - Max entries: 512K connections (default)
  - Khi full: evict connection lâu nhất không dùng
  - Không block! Không crash!

vs conntrack kernel (nf_conntrack):
  - nf_conntrack: spinlock on update
    → contention khi nhiều CPU
  - BPF LRU: lockless per-CPU design
    → scale tuyến tính với số CPU cores
```

---

## Per-CPU Hash Map: Counters lock-free

```
cilium_metrics (BPF_MAP_TYPE_PERCPU_HASH)
─────────────────────────────────────────
Mỗi CPU core có bản copy riêng của counter!
→ Không cần atomic operation
→ Không cần lock
→ Tốc độ cao nhất có thể

Khi user space đọc:
  bpf_map_lookup_elem() → [val_cpu0, val_cpu1, ...]
  user space sum() → total

Ứng dụng trong Cilium:
  - Đếm bytes/packets forwarded per policy
  - Đếm packets dropped per reason
  - Không bao giờ slow down high-traffic path
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Inspect BPF Maps trực tiếp

Chúng ta sẽ thực hành:

1. **List BPF maps:** `bpftool map list` để thấy tất cả maps Cilium tạo.
2. **Xem conntrack table:** `cilium bpf ct list global` — active connections.
3. **Xem policy map:** `cilium bpf policy list` — rules đang enforce.
4. **Demo O(1) vs O(n):** So sánh lookup time iptables vs BPF hash.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 27):** Kiến trúc Cilium — Operator, Agent, GoBGP, Hubble so sánh với Calico.
