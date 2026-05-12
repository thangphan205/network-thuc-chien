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

# Tập 39
## Troubleshooting Cilium: cilium status → hubble observe → cilium CLI

**Phần 3 — Cilium** · `#troubleshooting` `#cilium` `#debug` `#workflow` `#CLI`

---

## Mục tiêu tập này

- Systematic troubleshooting workflow cho Cilium
- cilium status: health check đầu tiên
- Phân biệt: control plane issue vs data plane issue
- Cheat sheet commands để bookmark

---

## Troubleshooting Hierarchy

```
Level 1: Cilium agent healthy?
  cilium status (trong pod) hoặc cilium-health

Level 2: Connectivity issue?
  hubble observe → xem có flows không, verdict gì

Level 3: Policy issue?
  cilium endpoint list → endpoint có policy enforce?
  cilium policy get → policy nào đang apply

Level 4: BPF issue?
  cilium bpf policy list → entries trong policy map
  bpftool prog list → BPF programs loaded

Level 5: Network issue?
  ping across nodes → basic connectivity
  cilium-health → node-to-node health check
```

---

## Level 1: cilium status

```bash
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium -o name | head -1)

kubectl -n kube-system exec -it $CILIUM_POD -- cilium status

# Healthy output:
# KVStore:                Ok   etcd:...
# Kubernetes:             Ok   1.29+
# Kubernetes APIs:        ["cilium/v2::CiliumNetworkPolicy"]
# KubeProxyReplacement:   True  [eth0 (Direct Routing)]
# Host Routing:           Legacy
# Cilium:                 Ok    1.15.x
# NodeMonitor:            Listening for events on 4 CPUs
# Cilium health daemon:   Ok
# IPAM:                   IPv4: 5/254 allocated
# BPF Maps:               dynamic sizing of BPF maps
# Unreachable nodes:      0

# ⚠️  Warning signs:
# KVStore:                Failure ← etcd problem
# Kubernetes:             Failure ← API server issue
# Unreachable nodes:      2       ← Network partition
```

---

## Level 2: hubble observe — Xác nhận flow

```bash
# Setup: port-forward hubble relay nếu chưa
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Pattern 1: Xem có flow nào không
hubble observe --namespace production --since 5m

# Pattern 2: Chỉ DROPPED
hubble observe --namespace production \
  --verdict DROPPED --since 10m

# Pattern 3: Từ specific pod
hubble observe --from-pod production/frontend \
  --since 5m

# Pattern 4: Đến specific port (database?)
hubble observe --to-port 5432 --namespace production

# Output bình thường (no issue):
# production/frontend → production/backend:8080  FORWARDED

# Output có issue:
# production/frontend → production/backend:8080  DROPPED  Policy denied
```

---

## Level 3: Policy troubleshooting

```bash
# Xem endpoints và trạng thái policy
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium endpoint list
# ENDPOINT  POLICY-INGRESS  POLICY-EGRESS  IDENTITY
# 1234      Enabled         Disabled       7891     ← backend, ingress enforced
# 5678      Disabled        Disabled       12345    ← frontend, no policy

# Xem policy cho một endpoint cụ thể
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium endpoint get 1234

# Xem tất cả policy đang active
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium policy get

# Xem ingress policy rules cho endpoint
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium bpf policy list 1234
# Egress/Ingress allowed identities:
# DIRECTION  IDENTITY  PORT  PROTO  VERDICT
# ingress    12345     8080  TCP    Allow   ← frontend (id=12345) → port 8080 OK
# ingress    ANY       ANY   ANY    Deny    ← default deny
```

---

## Level 4: BPF verification

```bash
# Xem BPF programs loaded
kubectl -n kube-system exec -it $CILIUM_POD \
  -- bpftool prog list | grep -E "name|type|id"

# Xem policy map entries cho endpoint
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium bpf policy get 1234

# Verify TC programs trên veth
POD_VETH=$(kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium endpoint get 1234 | grep "interface-name" | awk '{print $2}')

kubectl -n kube-system exec -it $CILIUM_POD \
  -- tc filter show dev $POD_VETH ingress

# Verify conntrack entries
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium bpf ct list global | wc -l
# Expected: >0 nếu có active connections
```

---

## Level 5: Node connectivity

```bash
# cilium-health: node-to-node connectivity check
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium-health status

# Output:
# Probe time:   2026-05-12T14:23:05Z
# Nodes:
#   k8s-master (localhost):
#     Host connectivity to k8s-master:   Ok   0.208ms
#     Endpoint connectivity to k8s-master: Ok 0.354ms
#   k8s-worker1:
#     Host connectivity to k8s-worker1:  Ok   0.891ms
#     Endpoint connectivity to k8s-worker1: Ok 1.234ms
#   k8s-worker2:
#     Host connectivity to k8s-worker2:  TIMEOUT  ← Problem!
#     Endpoint connectivity to k8s-worker2: TIMEOUT

# → Vấn đề ở node k8s-worker2!
# → Check: node taining, network partition, Cilium agent crash
```

---

## Troubleshooting Cheat Sheet

```bash
# Health check
kubectl -n kube-system exec -it $CILIUM_POD -- cilium status
kubectl -n kube-system exec -it $CILIUM_POD -- cilium-health status

# Flow debugging
hubble observe --namespace <ns> --verdict DROPPED --follow
hubble observe --from-pod <ns/pod> --to-pod <ns/pod>

# Policy debugging
kubectl -n kube-system exec -it $CILIUM_POD -- cilium endpoint list
kubectl -n kube-system exec -it $CILIUM_POD -- cilium policy get
kubectl -n kube-system exec -it $CILIUM_POD -- cilium bpf policy list <endpoint-id>

# BPF debugging
kubectl -n kube-system exec -it $CILIUM_POD -- cilium bpf endpoint list
kubectl -n kube-system exec -it $CILIUM_POD -- cilium bpf ct list global | wc -l
kubectl -n kube-system exec -it $CILIUM_POD -- bpftool prog list

# FQDN/DNS debugging
kubectl -n kube-system exec -it $CILIUM_POD -- cilium fqdn cache list

# Connectivity test (Cilium built-in)
kubectl -n kube-system exec -it $CILIUM_POD -- \
  cilium connectivity test --test pod-to-pod
```

---

## So sánh: Calico vs Cilium troubleshooting

| Step | Calico | Cilium |
| :--- | :--- | :--- |
| Health check | `calicoctl node status` | `cilium status` |
| Flow visibility | tcpdump / iptables-save | `hubble observe` |
| Policy applied? | `calicoctl get wep` | `cilium endpoint list` |
| Drop reason | iptables -L chain | Hubble `drop_reason` field |
| Node connectivity | ping + route check | `cilium-health status` |
| Policy rules active | iptables -L cali-* | `cilium bpf policy list` |

```
Key difference:
  Calico: manual correlation của nhiều tools
  Cilium: hubble observe cung cấp "why" ngay lập tức
```

> **Tập tiếp theo (Tập 40): Cilium Lab 1 — Pod label sai, Hubble show "Policy denied" ngay lập tức.**
