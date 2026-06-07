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

# Tập 18
## Troubleshooting Calico: calicoctl → ip route → iptables-save

**Phần 2 — Calico** · `#troubleshooting` `#debug` `#methodology` `#calicoctl`

---

## Mục tiêu tập này

- Học workflow debug Calico có hệ thống (không đoán mò)
- Dùng đủ bộ tool: calicoctl, ip route, iptables-save, tcpdump
- Debug 3 scenario khác nhau trong lab
- Biết lúc nào check control plane vs data plane

**Prerequisites:** Cluster Calico đang chạy, có network policies

---

## Workflow debug Calico — 5 bước

```
Symptom: Pod A không connect được Pod B

Bước 1: CHECK BASICS
  kubectl get pods -o wide       # Pod đang chạy? Đúng node?
  kubectl get endpoints          # Service có endpoints chưa?

Bước 2: CHECK BGP (nếu dùng BGP mode)
  calicoctl node status          # BGP sessions UP?
  ip route show                  # Có route đến subnet của Pod B?

Bước 3: CHECK IPTABLES POLICY
  iptables-save | grep cali      # Calico rules có được tạo chưa?
  iptables -L cali-FORWARD -n    # Chain đang làm gì?

Bước 4: TRACE PACKET
  tcpdump -i any host <pod-ip>   # Packet có đến nơi không?

Bước 5: CHECK FELIX LOGS
  kubectl logs -n calico-system calico-node  # Felix error?
```

---

## Control Plane vs Data Plane

```
Control Plane (Felix/BIRD quyết định):
  calicoctl node status       → BGP session state
  calicoctl get workloadep    → Felix biết Pod không?
  kubectl get networkpolicy   → Policy đang active?

Data Plane (kernel thực thi):
  ip route show               → Route có trong kernel?
  iptables -L cali-FORWARD    → Rule có trong iptables?
  conntrack -L | grep <ip>    → Connection state?
  tcpdump -i any host <ip>    → Packet thực sự đi đâu?

"BGP UP" ≠ "Routing OK"
"Policy applied" ≠ "iptables rule tồn tại"
→ Phải kiểm tra CẢ HAI tầng
```

---

## Debug Command Toolkit

```bash
# Control plane
calicoctl node status                        # BGP sessions
calicoctl get workloadendpoint               # Pod endpoints Felix biết
calicoctl get networkpolicy --all-namespaces # Tất cả policies

# Data plane
ip route show | grep 10.244                  # Pod subnet routes
iptables-save | grep cali | wc -l            # Số Calico rules
iptables -L cali-FORWARD -nv --line-numbers  # Forward chain (packet count!)
conntrack -L -p tcp | grep <pod-ip>          # TCP connection state

# Packet trace (TEMP, xóa sau khi debug)
iptables -I FORWARD 1 -j LOG --log-prefix "DBG: "
dmesg -w | grep DBG

# Logs
kubectl logs -n calico-system daemonset/calico-node -c calico-node | tail -50
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Debug 3 Scenarios

Chúng ta sẽ thực hành 3 scenario debug theo workflow 5 bước:

1. **Scenario 1:** Policy deny không rõ lý do — debug qua `kubectl get networkpolicy` và `calicoctl get workloadendpoint`.
2. **Scenario 2:** BGP route bị mất tạm thời sau restart — debug qua `calicoctl node status` và `ip route`.
3. **Scenario 3:** Label typo — policy không match Pod — debug qua `--show-labels`.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Lab 1 — "Pod thiếu label" connection timeout bí ẩn.
