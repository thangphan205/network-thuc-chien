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

# Tập 29
## Kiến trúc Cilium: Operator, Agent, GoBGP, Hubble — So sánh với Calico

**Phần 3 — Cilium** · `#cilium` `#architecture` `#operator` `#gobgp` `#hubble`

---

## Mục tiêu tập này

- Map kiến trúc Cilium: mỗi component làm gì
- So sánh với Calico (Felix ↔ Agent, BIRD ↔ GoBGP, không có ↔ Hubble)
- Cilium Operator vs Tigera Operator
- Luồng policy update từ API server đến BPF Map

---

## Kiến trúc tổng quan

```
┌─────────────────────────────────────────────────────────┐
│                    K8s Control Plane                    │
│  API Server ──── etcd                                   │
└──────────────┬──────────────────────────────────────────┘
               │ watch
    ┌──────────▼──────────┐
    │   Cilium Operator   │  ← 1 instance per cluster
    │  (manages CRDs,     │    (vs Tigera Operator)
    │   IPAM allocation)  │
    └──────────┬──────────┘
               │ coordinates
    ┌──────────▼──────────────────────────────────┐
    │            Cilium Agent (DaemonSet)         │
    │  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
    │  │  Policy  │  │  GoBGP   │  │  Hubble  │  │
    │  │  Engine  │  │ (optional│  │  Server  │  │
    │  └────┬─────┘  └──────────┘  └──────────┘  │
    │       │ write BPF Maps                      │
    │  ┌────▼─────────────────────────────────┐   │
    │  │           BPF Programs               │   │
    │  │  (XDP, TC ingress/egress, sockops)   │   │
    └──└──────────────────────────────────────┘───┘
```

---

## Cilium Agent — Trái tim của Cilium

```
cilium-agent (chạy trên mỗi Node):
  ├── Policy Manager
  │     Watch NetworkPolicy + CiliumNetworkPolicy từ API server
  │     Compile policy → BPF Map entries
  │
  ├── Endpoint Manager
  │     Track tất cả Pod trên node
  │     Assign identity (numeric ID, không phải IP!)
  │
  ├── IPAM Controller
  │     Allocate Pod IP (dùng Operator để coordinate)
  │
  ├── GoBGP (optional)
  │     BGP speaker thay thế BIRD
  │     Support BGP peering với ToR switch
  │
  └── Hubble Observer
        Record network events vào ring buffer
        Serve gRPC API cho hubble-relay
```

---

## Calico vs Cilium: Component mapping

| Calico | Cilium | Khác biệt |
| :--- | :--- | :--- |
| **Felix** | **cilium-agent** | Cilium agent làm nhiều hơn (IPAM, BGP, observe) |
| **BIRD** | **GoBGP (built-in)** | GoBGP là Go lib, không phải process riêng |
| **Typha** | **Cilium Operator** | Operator focus vào CRD management |
| **calicoctl** | **cilium CLI** | Similar nhưng Cilium CLI tích hợp Hubble |
| **Calico datastore** | **K8s CRDs** | Cilium không cần etcd riêng |
| *(không có)* | **Hubble** | Cilium có built-in observability |

---

## Cilium Identity: Thay vì IP dùng Security Identity

```
Calico model:
  Policy: "allow src_ip=10.244.1.5 → dst_port=8080"
  Vấn đề: Pod restart → IP thay đổi → policy "miss"

Cilium model:
  Identity = hash(Pod labels) = số nguyên (ví dụ: 12345)
  Policy: "allow identity=12345 → dst_port=8080"
  
  Pod labels: {app=frontend, env=prod}
  → Identity: sha256({app=frontend,env=prod}) mod 2^16 = 7891

  Pod restart → IP mới nhưng labels không đổi → identity không đổi
  → Policy tự động apply cho Pod mới!

Trong BPF Map:
  cilium_lxc: {endpoint_id, identity, ip_addr, ...}
```

---

## Lab: Xem Cilium components

```bash
multipass shell k8s-master

# Xem tất cả Cilium pods
kubectl -n kube-system get pods -l k8s-app=cilium
# NAME                READY   STATUS    NODE
# cilium-xxxxx        1/1     Running   k8s-master
# cilium-yyyyy        1/1     Running   k8s-worker1
# cilium-zzzzz        1/1     Running   k8s-worker2

# Xem Cilium Operator
kubectl -n kube-system get pods -l name=cilium-operator
# cilium-operator-xxxxx  1/1  Running

# Cilium status tổng quan
kubectl -n kube-system exec -it \
  $(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1) \
  -- cilium status
```

---

## Lab: Xem endpoints và identities

```bash
CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1)

# Xem endpoints Cilium đang manage
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium endpoint list
# OUTPUT:
# ENDPOINT  POLICY (ingress)  POLICY (egress)  IDENTITY  IPv4
# 123       Disabled          Disabled          7891      10.244.1.5
# 456       Enabled           Enabled           12345     10.244.1.8

# Xem identity details
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium identity list
# IDENTITY  LABELS
# 7891      k8s:app=frontend;k8s:env=prod
# 12345     k8s:app=backend;k8s:env=prod

# Xem BPF endpoint map
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium bpf endpoint list
```

---

## Key Takeaways

**Kiến trúc Cilium: unified agent design**

```
Calico cần:
  Felix + BIRD + Typha + calicoctl + Grafana (external)
  = 4+ components phải configure riêng

Cilium cần:
  cilium-agent (all-in-one) + Hubble (built-in)
  = 1 agent làm tất cả

Cilium Identity model > IP-based model:
  Pod restart không break policy
  Label change → identity change → policy update tức thì

Operator vs Felix:
  Cilium Operator: cluster-wide coordination, CRD management
  cilium-agent: per-node execution, BPF programming
```

> **Tập tiếp theo (Tập 30): 3 Hook Points của eBPF — XDP, TC và sockops làm gì khác nhau?**
