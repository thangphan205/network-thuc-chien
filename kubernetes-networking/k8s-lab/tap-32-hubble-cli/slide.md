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

# Tập 32
## Hubble CLI: `hubble observe` — Debug real-time không cần SSH vào Pod

**Phần 3 — Cilium** · `#hubble` `#observability` `#CLI` `#debug` `#flows`

---

## Mục tiêu tập này

- Hubble: network flow recorder + query engine built into Cilium
- Setup hubble CLI và kết nối với cluster qua port-forward
- 10+ command patterns quan trọng nhất
- Lab: debug "connection refused" trong 30 giây (không cần SSH)

**Prerequisites:** Cilium + Hubble Relay running (từ Tập 23)

---

## Hubble: Thay đổi cách debug hoàn toàn

```
Trước Hubble (Calico/Flannel):
  "Pod A không kết nối được Pod B":
  1. SSH vào Node A
  2. kubectl exec -it podA -- bash
  3. tcpdump -i eth0 ...   (cần root)
  4. iptables -L ... | grep ...
  5. Đọc log Felix ...
  → 15-30 phút mỗi incident

Với Hubble:
  hubble observe --pod production/pod-a \
    --verdict DROPPED --follow
  → Thấy ngay: "Policy denied: pod-a → pod-b:8080"
  → 30 giây!

Hubble record EVERY packet decision trong cluster!
```

---

## Hubble Architecture

```
┌─────────────────────────────────────────────────┐
│               Cilium Agent (Node)               │
│  BPF Programs ──record flow──▶ Ring Buffer      │
│  (per packet decision)         (4096 events/node)│
│                ▲                                │
│                │ gRPC                           │
│          Hubble Server                          │
└────────────────┬────────────────────────────────┘
                 ▲ gRPC (all nodes)
          ┌──────┴───────┐
          │ Hubble Relay │  ← Aggregate từ ALL nodes
          └──────┬───────┘
                 ▲ gRPC
          ┌──────┴───────┐
          │  hubble CLI  │  ← Your terminal
          └──────────────┘
```

---

## hubble observe: Syntax cơ bản

```bash
# Tất cả flows
hubble observe

# Chỉ xem DROPPED (bị block bởi policy)
hubble observe --verdict DROPPED

# Chỉ xem FORWARDED
hubble observe --verdict FORWARDED

# Filter theo namespace
hubble observe --namespace production

# Từ Pod cụ thể
hubble observe --from-pod production/frontend

# Từ Pod này đến Pod kia
hubble observe \
  --from-pod production/frontend \
  --to-pod production/backend

# Real-time follow (như tail -f)
hubble observe --follow --verdict DROPPED

# HTTP flows only (L7)
hubble observe --protocol http
```

---

## Đọc Hubble output

```
$ hubble observe --namespace production --verdict DROPPED

TIMESTAMP     SOURCE                 DEST                  VERDICT   REASON
14:23:05.123  production/frontend    production/backend:8080  DROPPED   Policy denied
14:23:07.891  production/attacker    production/backend:8080  DROPPED   Policy denied

Với --output json:
{
  "flow": {
    "time": "2026-05-12T14:23:05Z",
    "source": {"namespace": "production", "pod_name": "frontend"},
    "destination": {"namespace": "production", "pod_name": "backend"},
    "l4": {"TCP": {"destination_port": 8080}},
    "verdict": "DROPPED",
    "drop_reason": "Policy denied"
  }
}
```

---

## Useful filters cheat sheet

```bash
# Tất cả egress drop từ namespace
hubble observe --verdict DROPPED --from-namespace production

# HTTP 403/4xx/5xx
hubble observe --protocol http --http-status-code 403

# Flows đến specific port
hubble observe --to-port 5432      # Database connections

# Từ IP cụ thể
hubble observe --from-ip 10.244.1.5

# JSON output cho scripting
hubble observe --verdict DROPPED --output json \
  | jq '.flow | {src: .source.pod_name, dst: .destination.pod_name}'

# Summarize: ai drop nhiều nhất
hubble observe --verdict DROPPED --namespace production \
  --output json \
  | jq -r '.flow.source.pod_name' \
  | sort | uniq -c | sort -rn | head -5
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Debug với Hubble trong 30 giây

Chúng ta sẽ thực hành:

1. **Setup hubble CLI + port-forward** Hubble Relay.
2. **Deploy production stack** với default deny policy.
3. **Xem Hubble detect drops real-time** — không cần SSH vào pod.
4. **Fix policy** và verify Hubble thấy FORWARDED.
5. **Cheat sheet drills** — thực hành các filter patterns quan trọng.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 33):** Hubble UI — Service Map tự động và DROPPED màu đỏ.
