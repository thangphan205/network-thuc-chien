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

# Tập 37
## Hubble UI: Service Map tự động & DROPPED màu đỏ

**Phần 3 — Cilium** · `#hubble` `#UI` `#servicemap` `#visualization` `#observability`

---

## Mục tiêu tập này

- Hubble UI cung cấp gì mà CLI không có — visual topology
- Service Map: tự động vẽ từ real traffic, không cần config
- Đọc visual flows: GREEN (forwarded) vs RED (dropped)
- Lab: mở Hubble UI và trace incident trực quan

**Prerequisites:** Cilium + Hubble UI running (từ Tập 27)

---

## Hubble UI: Web dashboard cho Hubble data

```
Hubble UI = Giao diện web tự động generated từ traffic
  ┌────────────────────────────────────────────────┐
  │           Service Map View                     │
  │                                                │
  │  [frontend] ──GREEN──▶ [backend]               │
  │      │                                         │
  │      └──RED──▶ [database]  ← DROPPED!          │
  │                                                │
  │  Filter: namespace, pod, verdict               │
  │  Timeline: click edge → see packet list        │
  │  Detail: src/dst/verdict/timestamp/HTTP path   │
  └────────────────────────────────────────────────┘

Không cần config! Hubble tự vẽ từ observed traffic.
Edge thickness = traffic volume.
```

---

## Service Map: Zero-config network topology

```
Khi cluster có:
  frontend → backend → database
  prometheus → backend (scrape /metrics)
  frontend → external-api.com

Hubble UI tự động:
  1. Observe tất cả flows
  2. Group theo Service/Pod label
  3. Draw edges với color:
     GREEN  = Majority FORWARDED
     YELLOW = Some DROPPED
     RED    = Majority DROPPED
  4. Edge thickness = traffic volume

Không cần:
  - Vẽ tay topology diagram
  - Update khi thêm/xóa service
  - Instrument application code
  
"Cluster tự document network topology của nó"
```

---

## Các views trong Hubble UI

```
1. Service Map View:
   Tổng quan topology, màu sắc alert
   Best for: "Cluster của tôi đang làm gì?"

2. Flow List View (click edge/node):
   Chi tiết từng packet:
   src → dst | verdict | HTTP path | timestamp
   Best for: "Tại sao connection này bị drop?"

3. Filter Bar:
   namespace, pod name, verdict, protocol, IP
   Best for: Focus vào 1 service trong cluster lớn

4. Namespace selector:
   Switch namespace để xem topology riêng
   Best for: Multi-tenant cluster

Tips:
   RED edges = immediate action items
   Click edge → xem flows → identify policy
   Fix policy → watch edge turn GREEN real-time
```

---

## Hubble CLI vs Hubble UI

```
hubble observe CLI:
  ✅ Scripting, automation, CI/CD checks
  ✅ JSON output → jq → alerting
  ✅ Quick one-off queries
  Pattern: "give me flows matching condition X"

Hubble UI:
  ✅ Onboarding new team members ("đây là cluster của ta")
  ✅ Architecture review ("service nào gọi service nào?")
  ✅ Incident review ("khi nào edge này đỏ?")
  ✅ Visual debugging ("ai đang DROP traffic?")
  Pattern: "show me what's happening visually"

Dùng cả hai: CLI cho daily ops, UI cho reviews
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Mở Hubble UI và trace incident

Chúng ta sẽ thực hành:

1. **Port-forward Hubble UI** và mở trong browser.
2. **Deploy frontend/backend/database** với traffic patterns.
3. **Apply policy chặn** frontend → database trực tiếp.
4. **Quan sát Service Map:** GREEN edge (frontend→backend), RED edge (frontend→database).
5. **Click RED edge** và xem packet list với policy denial reason.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 38):** Hubble Metrics — `hubble_drop_total`, `http_requests` và chọn đúng tool cho đúng tình huống.
