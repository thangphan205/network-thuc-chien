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
  section.warn { background: linear-gradient(135deg, #1a0800 0%, #0d1021 100%); }
  section.warn h2 { color: #f87171; border-bottom-color: #f87171; }
---

<!-- _class: ep -->

# Tập 21
## Lab 3: WireGuard MTU Black Hole — File nhỏ OK, file lớn fail

**Phần 2 — Calico Labs** · `#WireGuard` `#MTU` `#PMTUD` `#lab` `#BlackHole`

---

## Mục tiêu tập này

- Reproduce PMTUD Black Hole với WireGuard MTU sai
- Chứng minh pattern: same-node OK, cross-node fail
- Debug: ping DF bit xác định MTU thực tế
- Fix: wireguardMTU đúng + MSS Clamping

**Prerequisites:** Cluster Calico, Ubuntu 26.04 (WireGuard kernel built-in)

---

## Tình huống thực tế

```
Ticket từ Backend team:
"Upload file ảnh < 1MB: OK.
 Upload file video > 5MB: hang mãi, không xong.
 Chỉ xảy ra khi upload qua Service vào Pod trên Node khác.
 Cùng Node thì OK.
 WireGuard đang bật trên cluster."

Dấu hiệu đặc trưng:
  ✓ "cross-node"
  ✓ "large file"
  ✓ "WireGuard bật"
  → Nghi ngờ PMTUD Black Hole ngay!
```

---

<!-- _class: warn -->

## PMTUD Black Hole — Cơ chế

```
MTU interface Pod = 1500 (sai, WireGuard cần 1420)
TCP packet lớn: 1450 bytes + DF bit = 1

Path:
  Pod A → [WireGuard] → 1450 + 80 bytes WG header = 1530
  Physical MTU = 1500 → 1530 > 1500 → muốn fragment
  DF = 1 → KHÔNG ĐƯỢC fragment
  Router SILENTLY DROP (không gửi ICMP fragmentation needed)

Kết quả:
  Sender không biết → tiếp tục gửi packet lớn
  → Connection hang mãi, không có error message
  
File nhỏ (< 1420 bytes): fit trong 1 packet → OK
File lớn (> 1420 bytes): bị drop → hang
```

---

## Debug Pattern

```bash
# 1. Cross-node vs same-node
# Same-node: không qua WireGuard tunnel → OK
# Cross-node: qua WireGuard tunnel → fail

# 2. Test với DF bit
ping -s 1400 -M do <cross-node-pod-ip>
# Nếu MTU sai → "message too long, mtu=1420"
# Kernel biết MTU thực = 1420 dù interface nói 1500

# 3. Fix MTU
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec":{"wireguardMTU":1420}}'

# 4. MSS Clamping thêm bảo vệ
# Calico tự cài iptables mangle rule khi set wireguardMssClamp
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Reproduce và Fix PMTUD Black Hole

Chúng ta sẽ thực hành:

1. **Setup bug:** Bật WireGuard với `wireguardMTU: 1500` (sai).
2. **Reproduce:** File nhỏ OK, file lớn 5MB hang → timeout.
3. **Prove same-node OK:** Deploy server cùng node → file lớn pass (không qua WireGuard).
4. **Debug:** `ping -M do -s 1440` xác định MTU thực tế.
5. **Fix:** Set `wireguardMTU: 1420`, verify file lớn pass.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Lab 4 — Cross-namespace AND/OR bug, Prometheus không scrape được.
