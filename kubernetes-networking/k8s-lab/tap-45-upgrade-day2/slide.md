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
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 45
## Cilium Upgrade + Day-2 Operations — Zero-Downtime Lifecycle Management

**Phần 3 — Cilium** · `#upgrade` `#day2` `#operations` `#reliability` `#maintenance`

---

## Day-2 Questions (Mọi engineer hỏi trước khi deploy)

```
Q1: "Upgrade Cilium version như thế nào? Có downtime không?"
→ helm upgrade --reuse-values --atomic
→ DaemonSet rolling update: 1 node at a time
→ Zero downtime nếu có nhiều hơn 1 node

Q2: "Node cần maintenance, drain xong thì Cilium làm gì?"
→ --ignore-daemonsets: Cilium agent vẫn chạy trên node đang drain
→ Agent tắt sau khi tất cả user pods đã rời node
→ Uncordon: agent restart và sync BPF state

Q3: "cilium-agent OOMKilled hoặc crash — pods có mất network không?"
→ KHÔNG (đây là điểm khác biệt lớn nhất vs kube-proxy)
→ BPF programs đã loaded vào kernel
→ Kernel state tồn tại độc lập với agent process
→ Existing connections: unaffected
→ New pod creation: blocked ~10-25s (đến khi agent recover)
```

---

## Upgrade: DaemonSet Rolling Update

```
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values      ← Giữ nguyên tất cả custom flags
  --version 1.16.y    ← Target version
  --atomic            ← Rollback tự động nếu fail
  --timeout 5m

Timeline trên 3-node cluster:
  T+0s:   controlplane: Terminating cilium-old → Creating cilium-new
  T+30s:  controlplane: cilium-new Running
  T+30s:  worker1: Terminating cilium-old → Creating cilium-new
  T+60s:  worker1: cilium-new Running
  T+60s:  worker2: Terminating cilium-old → Creating cilium-new
  T+90s:  worker2: cilium-new Running
  T+90s:  Upgrade complete! Total: ~90s, 0 downtime
```

---

## Upgrade: Compatibility Matrix

```
Cilium version    K8s supported range
──────────────    ────────────────────
1.14.x            1.24 → 1.29
1.15.x            1.26 → 1.30
1.16.x            1.27 → 1.32
1.17.x            1.28 → 1.33

Rules:
  ✅ Always upgrade Cilium BEFORE K8s
  ✅ Max 2 minor versions per upgrade (1.14 → 1.16: OK)
  ❌ Skip 3+ minor versions NOT supported
  ✅ Patch versions (1.16.0 → 1.16.5): always safe

Checklist trước upgrade:
  1. helm get values cilium -n kube-system > backup.yaml
  2. Verify compatibility matrix
  3. Test trên staging cluster
  4. helm upgrade ... --dry-run (xem changes)
  5. Upgrade trong giờ thấp traffic
```

---

## Agent Crash: BPF Survives in Kernel

```
Architecture bình thường (kube-proxy):
  kube-proxy quản lý iptables rules
  kube-proxy crash → iptables rules bị stale → không update
  New Services → traffic không forward (kube-proxy phải running!)
  
Cilium khác:
  cilium-agent compile policy → load BPF programs vào kernel
  BPF programs: attached to network hooks trong kernel namespace
  
  cilium-agent crash:
    BPF programs: STILL RUNNING in kernel ← độc lập với agent
    Existing flows: UNAFFECTED
    iptables: không còn (Cilium đã replace)
    
  Chỉ bị ảnh hưởng khi agent down:
    - Tạo NEW pod: agent cần config veth + attach BPF → không thể
    - Policy UPDATE: agent cần recompile BPF → không thể
    - Labels CHANGE: agent cần recalculate identity → không thể
```

---

## Node Operations: Drain Behavior

```
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data

Sequence:
  1. Node marked Unschedulable (cordon)
  2. All non-DaemonSet pods: evicted
  3. DaemonSet pods (Cilium): IGNORED, still running
     → Cilium cần running để pods di chuyển có network
  4. Pod eviction complete
  5. Cilium DaemonSet pod còn chạy trên worker1

kubectl uncordon worker1:
  1. Node Schedulable again
  2. New pods can be scheduled on worker1
  3. Cilium DaemonSet pod: already running (never stopped)
  4. New pods: Cilium immediately configures BPF for them

Zero network interruption during maintenance ✅
```

---

## Helm History và Rollback

```bash
# Xem lịch sử upgrades
helm history cilium -n kube-system
# REVISION  UPDATED         STATUS     CHART         DESCRIPTION
# 1         Jan 01 10:00    superseded cilium-1.16.0  Install
# 2         Jan 15 14:00    superseded cilium-1.16.2  Upgrade
# 3         Feb 01 09:00    deployed   cilium-1.16.5  Upgrade

# Rollback nếu có vấn đề
helm rollback cilium 2 -n kube-system --wait
# → Reverts to revision 2 (cilium-1.16.2)
# → DaemonSet rolling update back (same rolling behavior)

# Verify rollback
helm list -n kube-system | grep cilium
# cilium  1.16.2  ...

# Best practice: backup values trước mỗi upgrade
helm get values cilium -n kube-system -o yaml \
  > cilium-values-$(date +%Y%m%d-%H%M).yaml
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Upgrade + Day-2

1. **Pre-upgrade:** Snapshot version, backup values, verify compatibility
2. **Helm upgrade:** Rolling update, monitor DaemonSet progress
3. **Verify:** No downtime, endpoint count unchanged
4. **Node drain:** Drain worker1, verify Cilium still running
5. **Agent crash:** Delete cilium-agent pod, observe BPF survives
6. **Rollback:** `helm rollback` về revision trước

👉 **Xem chi tiết trong `lab-guide.md`**

> **Tập tiếp theo (Tập 46):** BGP Control Plane — advertise pod CIDRs và LB IPs
