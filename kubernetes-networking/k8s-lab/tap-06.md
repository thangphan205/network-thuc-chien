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

# Tập 6
## Flannel là gì? Vấn đề Pod-to-Pod Communication mà nó giải quyết

**Phần 1 — Flannel** · `#flannel` `#CNI` `#overlay` `#flat-network`

---

## Mục tiêu tập này

- Giải thích bài toán Pod-to-Pod cross-node communication
- Quan sát trạng thái cluster trước và sau khi cài Flannel
- Hiểu khái niệm "flat network" và overlay network
- Thực hành ping cross-node Pod sau khi cài Flannel

**Prerequisites:** Cluster Ubuntu 26.04 (3 nodes) chưa có CNI

---

## Bài toán: 2 Pod, 2 Node, không nói chuyện được

```
Node 1 (192.168.64.10)         Node 2 (192.168.64.11)
┌───────────────────────┐      ┌───────────────────────┐
│ Pod A: 10.244.1.5/24  │      │ Pod B: 10.244.2.7/24  │
│ Default route:         │      │                       │
│  via 10.244.1.1 (cni0)│      │                       │
└───────────────────────┘      └───────────────────────┘

Pod A gửi packet đến 10.244.2.7:
  ip route show → không có route đến 10.244.2.0/24
  → packet bị DROP tại Node 1 (no route to host)
```

**Giải pháp Flannel:** tạo virtual network phẳng — mọi Pod thấy nhau dù ở Node nào.

---

## Flannel tạo "flat network" như thế nào?

**VXLAN mode (mặc định):**
```
Pod A (10.244.1.5) → cni0 → flannel.1 → [VXLAN encap]
                                              ↓ UDP 8472
                                         Node 2 eth0
                                              ↓ [VXLAN decap]
                                         flannel.1 → cni0 → Pod B (10.244.2.7)
```

**host-gw mode (tốc độ cao):**
```
Pod A (10.244.1.5) → cni0 → eth0 → [direct routing] → eth0 → cni0 → Pod B
Node 1 routing table: 10.244.2.0/24 via 192.168.64.11 dev eth0
```

---

<!-- _class: lab -->

## Lab: Reset cluster và cài Flannel

```bash
# Reset cluster để bắt đầu với không có CNI
# (Nếu đang chạy từ Tập 1 với Flannel, skip bước reset này)
multipass exec k8s-master -- sudo kubeadm reset -f
multipass exec k8s-worker1 -- sudo kubeadm reset -f
multipass exec k8s-worker2 -- sudo kubeadm reset -f

# Re-init cluster
MASTER_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
multipass exec k8s-master -- sudo kubeadm init \
  --apiserver-advertise-address=$MASTER_IP \
  --pod-network-cidr=10.244.0.0/16

# Setup kubeconfig
multipass exec k8s-master -- bash -c '
  mkdir -p $HOME/.kube
  sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config'

# Join workers
JOIN_CMD=$(multipass exec k8s-master -- sudo kubeadm token create --print-join-command)
multipass exec k8s-worker1 -- sudo $JOIN_CMD
multipass exec k8s-worker2 -- sudo $JOIN_CMD
```

---

## Lab: Quan sát trước khi cài Flannel

```bash
multipass shell k8s-master

# Node NotReady
kubectl get nodes
# NAME          STATUS     ROLES           AGE
# k8s-master    NotReady   control-plane   2m
# k8s-worker1   NotReady   <none>          45s
# k8s-worker2   NotReady   <none>          40s

# Không có route đến Pod subnets
multipass exec k8s-worker1 -- ip route show
# default via 192.168.64.1 dev eth0
# 192.168.64.0/24 dev eth0
# (Không có 10.244.x.x routes!)

# Cài Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Theo dõi quá trình
watch -n2 kubectl get nodes,pods -n kube-flannel
```

---

## Lab: Quan sát sau khi cài Flannel

```bash
# Sau ~60 giây: Nodes Ready
kubectl get nodes
# NAME          STATUS   ROLES           AGE
# k8s-master    Ready    control-plane   4m
# k8s-worker1   Ready    <none>          3m
# k8s-worker2   Ready    <none>          3m

# Interface mới trên worker1
multipass exec k8s-worker1 -- ip link show
# flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450  ← VXLAN tunnel
# cni0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450       ← Pod bridge

# Routes mới
multipass exec k8s-worker1 -- ip route show
# 10.244.0.0/24 via 10.244.0.0 dev flannel.1  ← Route đến master
# 10.244.1.0/24 dev cni0                      ← Local pod subnet
# 10.244.2.0/24 via 10.244.2.0 dev flannel.1  ← Route đến worker2
```

---

## Lab: Test cross-node pod communication

```bash
# Deploy 2 pods trên 2 node khác nhau
kubectl run pod-a --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker1"}}' -- sleep infinity
kubectl run pod-b --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker2"}}' -- sleep infinity

kubectl wait --for=condition=Ready pod/pod-a pod/pod-b --timeout=60s

# Lấy IPs
POD_A_IP=$(kubectl get pod pod-a -o jsonpath='{.status.podIP}')
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
echo "Pod A: $POD_A_IP (worker1), Pod B: $POD_B_IP (worker2)"

# Test ping cross-node
kubectl exec pod-a -- ping -c 3 $POD_B_IP
# PING 10.244.2.X: 3 packets, 3 received ✅ (qua VXLAN tunnel)

# Đo latency — sẽ thấy VXLAN overhead
kubectl exec pod-a -- ping -c 10 $POD_B_IP | tail -3
# rtt min/avg/max/mdev = 0.4/0.6/0.8/0.1 ms
```

---

## Key Takeaways

**Flannel giải quyết:**
```
Trước Flannel: 10.244.1.5 → 10.244.2.7 = FAILED (no route)
Sau Flannel:   10.244.1.5 → 10.244.2.7 = OK (VXLAN tunnel)
```

**Những gì Flannel tạo ra:**
- `flannel.1` — VXLAN tunnel endpoint (VTEP) trên mỗi Node
- `cni0` — Linux bridge, gateway cho Pods trên Node
- Routes: `10.244.X.0/24 via flannel.1` cho mỗi Node khác

**Flannel KHÔNG làm:**
- Không có NetworkPolicy (bất kỳ Pod nào cũng ping được Pod khác)
- Không có BGP
- Không có L7 policy
- Không có observability

> **Tập tiếp theo:** flanneld làm gì bên trong? Subnet assignment từ etcd hoạt động ra sao?
