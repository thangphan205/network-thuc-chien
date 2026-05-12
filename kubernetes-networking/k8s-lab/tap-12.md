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

# Tập 12
## Kiến trúc Calico: Felix, BIRD, Datastore — Ai làm gì?

**Phần 2 — Calico** · `#calico` `#felix` `#BIRD` `#datastore` `#architecture`

---

## Mục tiêu tập này

- Giải thích vai trò chính xác của Felix, BIRD, Typha
- Trace luồng từ NetworkPolicy CR → iptables rule trên Node
- Quan sát Felix log khi policy thay đổi (event-driven)
- Hiểu khi nào cần Typha và khi nào không cần

**Prerequisites:** Cluster từ Tập 11 với Calico đang chạy

---

## Tổng quan kiến trúc Calico

```
┌──────────────────────────────────────────────────────────┐
│               Kubernetes API Server                      │
│   NetworkPolicy, IPPool, BGPPeer, FelixConfiguration    │
└───────────────────────┬──────────────────────────────────┘
                        │ watch (via Typha nếu cluster lớn)
          ┌─────────────┼─────────────┐
          │             │             │
    ┌─────▼──────┐ ┌────▼───────┐ ┌──▼──────────┐
    │   Felix    │ │    BIRD    │ │    Typha    │
    │ (per node) │ │ (per node) │ │ (optional)  │
    │            │ │            │ │             │
    │ Policy →   │ │ BGP daemon │ │ Cache K8s   │
    │ iptables / │ │ Route adv. │ │ API → fan   │
    │ eBPF       │ │ peer nodes │ │ out to Felix│
    └────────────┘ └────────────┘ └─────────────┘
```

---

## Felix: Bộ não của Calico

**Felix chạy gì?**
- Watch K8s API (hoặc Typha) cho NetworkPolicy, Pod, Node updates
- Dịch NetworkPolicy → iptables chains hoặc eBPF programs
- Quản lý routes cho Pod IPs trên node này
- Báo cáo health của node qua `felix_` metrics

**Event-driven, không polling:**
```
NetworkPolicy thay đổi
    ↓
K8s API webhook → Felix nhận event trong ms
    ↓
Felix recalculate rules
    ↓
Felix atomic update iptables/eBPF (< 100ms)
    ↓
Traffic bị enforce ngay lập tức
```

**Không cần restart pod hay node!**

---

## BIRD: BGP cho Calico

**BIRD (Bird Internet Routing Daemon)** — BGP daemon của Calico.

```
Mỗi Node chạy 1 BIRD instance:
- Peer với BIRD của các Node khác (full mesh)
- Hoặc peer với Route Reflector
- Quảng bá: "Pod subnet 10.244.1.0/24 nằm ở tôi"
- Nhận route từ peer: "10.244.2.0/24 ở Node 2"
- Cài routes vào kernel routing table
```

**Khi nào BIRD hoạt động?**
- BGP mode (không dùng overlay)
- Peer với ToR switch datacenter
- Khi dùng VXLAN: BIRD vẫn chạy nhưng routes không cần thiết

---

<!-- _class: lab -->

## Lab: Xem Felix log real-time

```bash
multipass shell k8s-master

# Xem Felix log trên worker1
kubectl -n calico-system logs -f daemonset/calico-node -c calico-node \
  --node-name=k8s-worker1 | grep -i "felix\|policy\|endpoint"

# Trong terminal khác: thay đổi NetworkPolicy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-policy
spec:
  podSelector:
    matchLabels:
      app: frontend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: backend
EOF

# Felix log sẽ hiện:
# Dispatching update for endpoint key...
# Policy update: processing 1 policy update(s)
# Finished applying policy update in <X>ms
```

---

## Lab: Xem iptables chains Felix tạo ra

```bash
multipass shell k8s-worker1

# Calico tạo nhiều chains trong iptables
sudo iptables -L | grep "^Chain cali"
# Chain cali-FORWARD (1 references)
# Chain cali-INPUT (1 references)
# Chain cali-OUTPUT (1 references)
# Chain cali-from-host-endpoint
# Chain cali-from-wl-dispatch
# Chain cali-to-host-endpoint
# Chain cali-to-wl-dispatch
# Chain cali-fw-<endpoint-id>   ← Per-endpoint from-workload rule
# Chain cali-tw-<endpoint-id>   ← Per-endpoint to-workload rule

# Xem chain của frontend pod cụ thể
FRONTEND_EP=$(sudo calicoctl get workloadendpoint --node=k8s-worker1 | grep frontend | awk '{print $1}')
sudo iptables -L cali-fw-$FRONTEND_EP -n --line-numbers
```

---

## Lab: Calicoctl — CLI quản lý Calico

```bash
# Cài calicoctl
curl -L https://github.com/projectcalico/calico/releases/download/v3.29.0/calicoctl-linux-amd64 \
  -o calicoctl && chmod +x calicoctl && sudo mv calicoctl /usr/local/bin/

# Xem tất cả endpoints (Pods được Calico quản lý)
calicoctl get workloadendpoint
# WORKLOAD    NODE          NETWORKS        INTERFACE
# frontend    k8s-worker1   10.244.1.5/32   cali1234567

# Xem IP pools
calicoctl get ippool
# NAME                  CIDR           SELECTOR
# default-ipv4-ippool   10.244.0.0/16  all()

# Xem Felix configuration
calicoctl get felixconfig default -o yaml | head -30

# Node status (BGP và health)
calicoctl node status
```

---

## Lab: Typha — khi nào cần?

```bash
# Typha là cache layer giữa K8s API và Felix
# Mặc định: Không có Typha (cluster nhỏ < 50 nodes)
# Với > 50 nodes: nên bật Typha để giảm tải K8s API server

# Xem Typha có đang chạy không
kubectl -n calico-system get pods | grep typha
# calico-typha-xxxxx   1/1   Running   (tùy theo installation)

# Số lượng Felix instance connect đến Typha
kubectl -n calico-system logs deployment/calico-typha | grep "Connections"

# Tigera Operator tự động quyết định dùng Typha khi nodeCount > 3 nodes
kubectl -n tigera-operator get installation default -o jsonpath='{.spec}' | python3 -m json.tool
```

---

## Key Takeaways

| Component | Location | Trách nhiệm |
| :--- | :--- | :--- |
| **Felix** | DaemonSet, mỗi Node | Policy → iptables/eBPF, routes |
| **BIRD** | DaemonSet, mỗi Node | BGP route advertisement |
| **Typha** | Deployment, vài Pods | Cache K8s API cho Felix (cluster lớn) |
| **Tigera Operator** | Deployment | Quản lý lifecycle Calico components |

**Luồng policy:**
```
NetworkPolicy (YAML) → K8s API → [Typha] → Felix → iptables/eBPF
```

**Debug Felix:**
```bash
kubectl -n calico-system logs daemonset/calico-node -c calico-node
calicoctl get workloadendpoint
calicoctl node status
```

> **Tập tiếp theo:** iptables vs eBPF dataplane trong Calico — khi nào upgrade?
