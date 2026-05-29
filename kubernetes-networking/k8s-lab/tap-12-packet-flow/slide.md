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

# Tập 12 - Calico - Packet Flow
## veth pair & conntrack: Hành trình của 1 packet qua Calico

**Phần 2 — Calico** · `#packet-flow` `#veth` `#conntrack` `#iptables` `#trace`
![height:200px](https://www.tigera.io/app/uploads/2026/01/Calico-logo-2026-white-text.svg)
---

## Mục tiêu tập này

- Vẽ đầy đủ hành trình packet từ Pod A → Pod B qua Calico
- Dùng iptables LOG để trace packet qua từng chain
- Quan sát conntrack table entries
- Hiểu tại sao conntrack quan trọng với NetworkPolicy

**Prerequisites:** Cluster Calico từ Tập 9-13 đang chạy iptables mode

---

## Hành trình packet: Cùng Node

```
Pod A (10.244.1.5)
    │ eth0 (trong Pod ns)
    ▼
vethXXX (root ns)
    │
    ▼
iptables FORWARD chain
    ├── cali-FORWARD
    │     └── cali-from-wl-dispatch → cali-fw-<Pod-A-id>
    │              ← Egress policy của Pod A (được gửi đi không?)
    ▼
Routing table: 10.244.1.6/32 via vethYYY (Pod B's veth)
    │
    ▼
iptables FORWARD chain lại
    └── cali-to-wl-dispatch → cali-tw-<Pod-B-id>
              ← Ingress policy của Pod B (ai được vào?)
    │
    ▼
vethYYY → Pod B eth0 ✅
```

---

## Hành trình packet: Khác Node

```
Pod A (Node 1, 10.244.1.5) → Pod B (Node 2, 10.244.2.7)

Node 1:
  Pod A eth0 → vethXXX → iptables FORWARD
    → cali-fw-<Pod-A> (egress check) PASS
    → Routing: 10.244.2.0/24 via VXLAN/BGP
    → eth0 Node 1 → [network] → eth0 Node 2

Node 2:
  eth0 → iptables FORWARD
    → cali-to-wl-dispatch → cali-tw-<Pod-B> (ingress check) PASS
    → Route: 10.244.2.7/32 via vethYYY
    → vethYYY → Pod B eth0 ✅

Zero Trust: kiểm tra ở CẢ 2 đầu (egress Node 1 + ingress Node 2)
```

---

## conntrack: Biến stateless thành stateful

**Vấn đề:** TCP connection cần 2 chiều (request + response). Nếu chỉ allow ingress Pod B port 80, làm sao response đi ngược lại?

**conntrack giải quyết:**
```
Pod A → SYN → Pod B:80
  conntrack ghi: {10.244.1.5:random → 10.244.2.7:80} ESTABLISHED

Pod B → SYN-ACK → Pod A (ngược chiều)
  conntrack kiểm tra: "Có entry này không?"
  → Có! ESTABLISHED state → ALLOW (không cần rule riêng)

Kết quả: Chỉ cần 1 rule ALLOW ingress → response tự động được phép
```

---

## Calico chain order (iptables mode)

```
INPUT/FORWARD → cali-FORWARD
                  ├── cali-from-wl-dispatch (egress check, Pod nguồn)
                  └── cali-to-wl-dispatch   (ingress check, Pod đích)
                        └── cali-tw-<id> → ACCEPT hoặc DROP
```

**Debug tools:**
```bash
sudo iptables -t filter -L cali-FORWARD -n --line-numbers  # Xem rules
sudo conntrack -L | grep <ip>                               # Connection state
sudo iptables -t filter -I cali-FORWARD 1 -j LOG            # Trace (temp)
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Trace Packet qua iptables

Chúng ta sẽ thực hành:

1. **Setup LOG rules:** Cài iptables LOG để trace mọi packet qua Calico chains.
2. **Trace packet:** Gửi traffic và xem log hiện chain nào được traverse.
3. **Quan sát conntrack:** Xem ESTABLISHED entry được tạo và maintain.
4. **Demo DROP:** Apply policy, thấy DROP trong log và conntrack không có ESTABLISHED.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** NetworkPolicy cơ bản — Default Deny và viết Ingress Policy đúng cách.
