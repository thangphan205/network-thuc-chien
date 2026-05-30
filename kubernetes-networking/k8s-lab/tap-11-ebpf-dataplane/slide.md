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

# Tập 11 - Calico - eBPF
## iptables vs eBPF Dataplane trong Calico: O(n) vs O(1)

**Phần 2 — Calico** · `#eBPF` `#iptables` `#performance` `#dataplane` `#O(1)`
![height:200px](https://www.tigera.io/app/uploads/2026/01/Calico-logo-2026-white-text.svg)

---

## Mục tiêu tập này

- Giải thích tại sao iptables không scale với số lượng Pods lớn
- Hiểu eBPF Hash Map O(1) lookup vs iptables O(n)
- Bật eBPF dataplane trong Calico (cần kernel 5.3+)
- Xem `tc filter` programs được load vào network interfaces

**Prerequisites:** Cluster Calico từ Tập 9. Ubuntu 26.04 có kernel 6.x/7.x+ — đủ điều kiện eBPF.

---

## iptables: Thiết kế tuyến tính không scale

```
1000 Pods → ~10.000 iptables rules

Packet đến:
  Check rule 1?  No
  Check rule 2?  No
  Check rule 3?  No
  ...
  Check rule 10000? Yes → ACCEPT (hoặc DROP)

Complexity: O(n) — 10x Pod = 10x thời gian check

Thêm rule mới:
  Phải LOCK toàn bộ iptables table
  Rewrite TOÀN BỘ chain (không atomic)
  → Brief window khi rules inconsistent
  → Traffic có thể bị drop trong ms
```

---

## eBPF: Hash Map O(1)

```
BPF Hash Map:
  Key: {src_ip, dst_ip, dst_port, protocol}
  Value: ALLOW/DROP

Packet đến:
  Hash lookup → O(1) → ALLOW hoặc DROP
  Không phụ thuộc vào số lượng rules!

1000 Pods hay 100.000 Pods → cùng lookup time

Thêm rule mới:
  Atomic map update (single pointer swap)
  → Zero downtime, không traffic drop
  → BPF programs survive Agent restart
     (kernel giữ maps ngay cả khi Agent crash)
```

---

## So sánh iptables vs eBPF Calico

| Tiêu chí | iptables | eBPF |
| :--- | :--- | :--- |
| Lookup complexity | O(n) | **O(1)** |
| Update method | Lock + rewrite chain | **Atomic map update** |
| Traffic during update | Brief disruption | **Zero downtime** |
| Conntrack | Linux conntrack | **eBPF per-flow state** |
| Kube-proxy required | ✅ | ❌ (Calico thay thế) |
| Kernel requirement | Any | **5.3+ (Ubuntu 26.04: 6.x)** |

---

## Khi nào chọn eBPF mode?

```
✅ Production cluster, nhiều Pods (> 50)
✅ Cần low-latency policy enforcement
✅ Kernel 5.3+ (Ubuntu 26.04 luôn đủ)
✅ Muốn bỏ kube-proxy dependency

⚠️  Calico eBPF chưa thay thế hoàn toàn Cilium về features
⚠️  L7 policy: Calico eBPF không có (cần Cilium)
```

**Debug eBPF:**
```bash
tc filter show dev <interface> ingress   # eBPF programs
sudo bpftool prog list                   # Tất cả BPF programs
sudo bpftool map list                    # BPF maps (policy tables)
sudo bpftool map dump name calico_policy_map  # Policy entries
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Bật eBPF và Verify

Chúng ta sẽ thực hành:

1. **Kiểm tra kernel:** `uname -r` và BPF filesystem trên worker.
2. **Bật eBPF:** Patch kube-proxy + FelixConfiguration để bật eBPF dataplane.
3. **Xem programs:** `tc filter show` và `bpftool prog list` để verify BPF programs được load.
4. **So sánh rule count:** iptables rule count vs BPF map size.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Packet flow qua veth pair và conntrack — hành trình đầy đủ của 1 packet qua Calico.
