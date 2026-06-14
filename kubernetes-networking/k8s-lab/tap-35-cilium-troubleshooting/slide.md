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

# Tập 35
## Troubleshooting Cilium: cilium status → hubble observe → cilium CLI

**Phần 3 — Cilium** · `#troubleshooting` `#cilium` `#debug` `#workflow` `#CLI`

---

## Mục tiêu tập này

- Systematic troubleshooting workflow 5 levels cho Cilium
- `cilium status`: health check đầu tiên
- Phân biệt: control plane issue vs data plane issue
- Cheat sheet commands để bookmark

**Prerequisites:** Cilium + Hubble đang chạy (từ Tập 23)

---

## Troubleshooting Hierarchy — 5 Levels

```
Level 1: Cilium agent healthy?
  cilium status → KVStore, Kubernetes, BPF, Unreachable nodes

Level 2: Connectivity issue?
  hubble observe → có flows không, verdict gì, reason gì

Level 3: Policy issue?
  cilium endpoint list → endpoint có policy enforce?
  cilium bpf policy list → rules nào đang active

Level 4: BPF program issue?
  bpftool prog list → BPF programs có loaded không?
  cilium bpf endpoint list → endpoint mapping đúng không?

Level 5: Node-to-node issue?
  cilium-health status → node nào unreachable?
  ping across nodes → basic routing check
```

---

## Level 1: cilium status — Health check đầu tiên

```bash
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium -o name | head -1)

kubectl -n kube-system exec -it $CILIUM_POD -- cilium status

# Healthy:
# Kubernetes:         Ok   1.29+
# KubeProxyReplacement: True [eth0]
# Cilium:             Ok   1.15.x
# IPAM:               IPv4: 5/254 allocated
# Unreachable nodes:  0    ← Phải là 0!
# BPF Maps:           dynamic sizing OK

# Warning signs:
# KVStore:          Failure → etcd problem
# Kubernetes:       Failure → API server issue
# Unreachable nodes: 2     → Network partition!
```

---

## Level 2: hubble observe — Xác nhận flow

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Pattern 1: Có flow nào không?
hubble observe --namespace production --since 5m

# Pattern 2: Chỉ DROPPED
hubble observe --namespace production \
  --verdict DROPPED --since 10m

# Pattern 3: Từ/đến specific pod
hubble observe \
  --from-pod production/frontend \
  --to-pod production/backend

# Output bình thường:
# production/frontend → production/backend:8080  FORWARDED

# Output có issue:
# production/frontend → production/backend:8080
# DROPPED  Policy denied
# → Tìm thấy! Chuyển sang Level 3
```

---

## Level 3: Policy troubleshooting

```bash
# Xem endpoints và trạng thái policy enforcement
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium endpoint list
# ENDPOINT  POLICY-INGRESS  POLICY-EGRESS  IDENTITY  POD
# 1234      Enabled         Disabled       7891      backend
# 5678      Disabled        Disabled       12345     frontend

# Xem BPF policy map cho endpoint 1234
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium bpf policy list 1234
# DIRECTION  IDENTITY  PORT  PROTO  VERDICT
# ingress    12345     8080  TCP    Allow   ← frontend OK
# ingress    ANY       ANY   ANY    Deny    ← default deny

# Xem tất cả policy đang active
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium policy get
```

---

## Level 4: BPF verification

```bash
# BPF programs loaded?
kubectl -n kube-system exec -it $CILIUM_POD \
  -- bpftool prog list | grep -E "name|type"
# sched_cls  cil_from_container
# sched_cls  cil_to_container
# sock_ops   bpf_sockops

# Conntrack entries (có connections không?)
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium bpf ct list global | wc -l
# Expected: >0 nếu có active connections

# FQDN cache (nếu dùng toFQDNs)
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache list
```

---

## Level 5: Node connectivity

```bash
# cilium-health: node-to-node check
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium-health status

# Output:
# Nodes:
#   controlplane (localhost):
#     Host connectivity:     Ok   0.208ms
#     Endpoint connectivity: Ok   0.354ms
#   worker1:
#     Host connectivity:     Ok   0.891ms
#     Endpoint connectivity: Ok   1.234ms
#   worker2:
#     Host connectivity:     TIMEOUT  ← Problem!
#     Endpoint connectivity: TIMEOUT

# → Vấn đề ở node worker2!
# → Check: node taint, network partition, cilium agent crash
```

---

## Calico vs Cilium Troubleshooting

| Step | Calico | Cilium |
| :--- | :--- | :--- |
| Health check | `calicoctl node status` | `cilium status` |
| Flow visibility | tcpdump + iptables-save | `hubble observe` |
| Drop reason | Infer từ iptables chains | Hubble `drop_reason` field |
| Policy active? | `iptables -L cali-*` | `cilium bpf policy list` |
| Node connectivity | Ping + route check | `cilium-health status` |

```
Key difference:
  Calico: manual correlation nhiều tools, infer root cause
  Cilium: hubble observe → "drop_reason" nói thẳng
  
  "Policy denied" / "MTU exceeded" / "No route"
  → Immediate action item, không cần guessing
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Practise 5-level troubleshooting workflow

Chúng ta sẽ thực hành:

1. **Level 1:** `cilium status` — đọc health indicators và warning signs.
2. **Level 2:** `hubble observe` — xem flows và reproduce dropped packet.
3. **Level 3:** `cilium endpoint list` + `cilium bpf policy list` — xem policy active.
4. **Level 4:** `bpftool prog list` — verify BPF programs loaded.
5. **Level 5:** `cilium-health status` — kiểm tra node-to-node connectivity.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 36):** Cilium Lab 1 — Pod label sai, Hubble show "Policy denied" ngay lập tức.
