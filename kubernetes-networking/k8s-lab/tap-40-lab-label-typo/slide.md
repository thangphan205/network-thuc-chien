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

# Tập 40
## Cilium Lab 1: Pod label sai — Hubble show "Policy denied" ngay lập tức

**Phần 3 — Cilium Labs** · `#lab` `#label` `#hubble` `#debug` `#identity`

---

## Tình huống thực tế

```
Cùng scenario như Tập 22 (Calico Lab 1) — nhưng với Cilium:

Developer deploy backend-v2, quên label app=backend.
Frontend không gọi được backend-v2 (timeout).

Với Calico (Tập 22):
  Debug mất 5-15 phút:
  kubectl get pod --show-labels
  kubectl get networkpolicy → đọc selector
  iptables -L cali-tw-* (cần root)
  Infer root cause từ nhiều data sources

Với Cilium + Hubble:
  hubble observe --verdict DROPPED
  → "Policy denied" xuất hiện ngay trong 5 giây
  → Root cause rõ ràng không cần infer
  Debug: 30-60 giây!
```

---

## Tại sao Hubble nhanh hơn?

```
Calico drop flow:
  Packet → iptables DROP (silent)
  → Không log gì
  → Bạn phải tự tìm iptables chain
  → Tìm rule nào match
  → Infer "à, do thiếu label"

Cilium drop flow:
  Packet → BPF program: "lookup identity → no match → DROP"
  → Record event: {src, dst, verdict=DROPPED, reason="Policy denied"}
  → Hubble ring buffer
  → hubble observe → bạn đọc

Cilium không chỉ drop — nó LABEL drop reason
Hubble không chỉ show flow — nó explain WHY
```

---

## Cilium Identity model: Tại sao label quan trọng

```
Cilium Identity = hash(Pod labels)

backend-v2 KHÔNG có label:
  Labels: {}  →  Identity: 99999 (reserved: "unlabeled")
  
  Policy allow: fromEndpoints matchLabels {app: frontend}
  Frontend identity: 12345

  BPF lookup khi frontend → backend-v2:
    src_identity = 12345
    dst_endpoint = backend-v2 (endpoint 2345)
    policy map lookup: identity 12345 allowed? → NO
    → DROP → "Policy denied"

backend-v2 CÓ label app=backend:
  Labels: {app: backend}  →  Identity: 7891
  Policy allow: identity 12345 → port 8080 → ALLOW
  → FORWARDED
```

---

## Hubble: Debug vs Calico iptables

| Aspect | Calico | Cilium + Hubble |
| :--- | :--- | :--- |
| Drop information | Silent | `verdict=DROPPED, reason=Policy denied` |
| Root cause | Infer từ iptables | Hubble nói thẳng |
| Time to identify | 5-15 phút | 30-60 giây |
| Cần root/exec? | Thường có | Không (external hubble CLI) |
| Automation? | Khó | `hubble observe --output json \| jq` |

```
"Policy denied" trong Hubble = Label không match policy
First action: kubectl get pod --show-labels → verify labels
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Deploy với label bug, debug bằng Hubble

Chúng ta sẽ thực hành:

1. **Deploy backend-v2 không có label** + frontend + default deny policy.
2. **Start Hubble observer** trước khi reproduce.
3. **Trigger connection** từ frontend → thấy "Policy denied" trong Hubble.
4. **Trace root cause:** `cilium endpoint list` → thấy identity khác.
5. **Fix label** → Hubble confirm FORWARDED, identity thay đổi tức thì.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 41):** Cilium Lab 2 — L7 Policy thiếu HTTP method, HTTP 403 và quy trình confirm dev.
