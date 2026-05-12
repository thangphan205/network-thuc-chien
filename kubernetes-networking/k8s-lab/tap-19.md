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

# Tập 19
## Full Mesh vs Route Reflector: Bài toán n*(n-1)/2 khi cluster lớn

**Phần 2 — Calico** · `#BGP` `#RouteReflector` `#scaling` `#iBGP`

---

## Mục tiêu tập này

- Tính toán số BGP sessions với Full Mesh vs Route Reflector
- Cấu hình Route Reflector trong Calico
- Verify BGP sessions giảm sau khi dùng RR
- Hiểu trade-off giữa Full Mesh và RR

**Prerequisites:** Cluster Calico từ Tập 18 với BGP mode đang chạy

---

## Bài toán Full Mesh BGP

**Full mesh:** mỗi Node phải peer với mọi Node khác.

```
n = số Nodes
Số sessions = n × (n-1) / 2

3 nodes:   3 × 2 / 2   =    3 sessions  ✅
10 nodes:  10 × 9 / 2  =   45 sessions  ✅
50 nodes:  50 × 49 / 2 = 1225 sessions  ⚠️
100 nodes: 100 × 99/2  = 4950 sessions  ❌
500 nodes: 500 × 499/2 = 124750 sessions ❌❌
```

**Mỗi session tốn:**
- RAM: ~2-5 MB BIRD process per peer
- CPU: BGP keepalive + routing table sync
- Convergence time: tăng tuyến tính theo số sessions

---

## Route Reflector: Giải pháp iBGP scaling

```
Full Mesh (10 nodes):
N1 ── N2 ── N3
 \  ╲ │ ╱  /
  N4─ N5 ─N6
 /  ╱ │ ╲  \
N7 ── N8 ── N9  → 45 sessions

Route Reflector (10 nodes, 2 RR):
N1 ──┐
N2 ──┤
N3 ──┤
N4 ──┤──► RR1 ◄──► RR2   → 10 + 1 = 11 sessions!
N5 ──┤
N6 ──┤
N7 ──┤
N8 ──┤
N9 ──┘
```

**Trade-off:** RR là single point of failure → dùng 2-3 RR để HA.

---

<!-- _class: lab -->

## Lab: Xem Full Mesh hiện tại

```bash
multipass shell k8s-master

# Với 3 nodes: 3 sessions (full mesh)
for NODE in k8s-master k8s-worker1 k8s-worker2; do
  echo "=== $NODE BGP sessions ==="
  kubectl exec -n calico-system daemonset/calico-node -c calico-node \
    --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" \
    -- calico-node -bird-live 2>/dev/null
done

# Hoặc dùng calicoctl
calicoctl node status
# Sẽ thấy mỗi node có peer với 2 nodes khác = full mesh 3 nodes
```

---

## Lab: Cấu hình Route Reflector

```bash
# Bước 1: Tắt full mesh
calicoctl patch bgpconfiguration default \
  --patch '{"spec": {"nodeToNodeMeshEnabled": false}}'

# Bước 2: Label master node làm Route Reflector
kubectl label node k8s-master calico-route-reflector=true

# Bước 3: Annotate RR node với cluster ID
calicoctl patch node k8s-master \
  --patch '{"spec": {"bgp": {"routeReflectorClusterID": "1.0.0.1"}}}'

# Bước 4: Tạo BGPPeer: regular nodes → RR
calicoctl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: peer-to-rr
spec:
  nodeSelector: "!has(calico-route-reflector)"   # Regular nodes
  peerSelector: "has(calico-route-reflector)"    # Peer với RR nodes
EOF

# Bước 5: RR peer với RR (nếu có nhiều RR)
calicoctl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: rr-to-rr
spec:
  nodeSelector: "has(calico-route-reflector)"   # RR nodes
  peerSelector: "has(calico-route-reflector)"   # Peer với nhau
EOF
```

---

## Lab: Verify sessions giảm

```bash
# Sau khi cấu hình RR:
# Regular nodes (worker1, worker2) chỉ peer với master (RR)
# Master (RR) peer với cả 2 workers

calicoctl node status --node=k8s-worker1
# IPv4 BGP status
# PEER ADDRESS  PEER TYPE      STATE
# 192.168.64.10 node specific  up  ← Chỉ peer với master (RR)
# (không còn peer với worker2 trực tiếp!)

calicoctl node status --node=k8s-master
# PEER ADDRESS  PEER TYPE      STATE
# 192.168.64.11 node specific  up  ← worker1
# 192.168.64.12 node specific  up  ← worker2

# Test connectivity vẫn OK dù không còn full mesh
kubectl exec pod-a -- ping -c 3 <pod-b-ip>
# 3 packets transmitted, 3 received ✅ (route qua RR)
```

---

## Key Takeaways

| | Full Mesh | Route Reflector |
| :--- | :--- | :--- |
| Sessions (100 nodes) | 4950 | **~100** |
| RAM per node | Nhiều | Ít |
| Convergence speed | Nhanh (direct) | Phụ thuộc RR |
| Single point of failure | Không | **Có (dùng 2+ RR)** |
| Khi nào dùng | ≤ 50 nodes | **> 50 nodes** |

**Cấu hình nhanh RR:**
```bash
# Label RR nodes
kubectl label node <rr-node> calico-route-reflector=true

# Annotate cluster ID
calicoctl patch node <rr-node> \
  --patch '{"spec":{"bgp":{"routeReflectorClusterID":"1.0.0.1"}}}'

# Tắt full mesh + tạo BGPPeer selectors
```

> **Tập tiếp theo:** WireGuard trong Calico — mã hóa traffic nội bộ và bẫy MTU 1440 bytes.
