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

# Tập 7
## Kiến trúc Flannel: flanneld, etcd và CNI plugin hoạt động ra sao

**Phần 1 — Flannel** · `#flannel` `#flanneld` `#etcd` `#subnet` `#architecture`

---

## Mục tiêu tập này

- Giải thích vai trò của `flanneld`, etcd/K8s API, và CNI plugin
- Đọc subnet allocation từ K8s API (thay thế etcd trong K8s hiện đại)
- Trace luồng từ Node join cluster đến Pod có IP
- Quan sát file `subnet.env` mà flanneld tạo ra

**Prerequisites:** Cluster từ Tập 6 với Flannel đang chạy

---

## 3 thành phần của Flannel

```
┌─────────────────────────────────────────────────┐
│              Kubernetes API / etcd              │
│         /flannel.io/network/subnets/            │
│   Node1: 10.244.1.0/24  Node2: 10.244.2.0/24   │
└──────────────────────┬──────────────────────────┘
                       │ watch
          ┌────────────┼────────────┐
          ▼            ▼            ▼
    flanneld (N1)  flanneld (N2)  flanneld (N3)
    DaemonSet      DaemonSet      DaemonSet
    ─────────      ─────────      ─────────
    • Đăng ký      • Đăng ký      • Đăng ký
      subnet         subnet         subnet
    • Cấu hình     • Cấu hình     • Cấu hình
      VTEP/routes    VTEP/routes    VTEP/routes
    • Ghi           • Ghi           • Ghi
      subnet.env     subnet.env     subnet.env
          │
          ▼
    CNI plugin (bridge)
    Đọc subnet.env → gán IP cho Pod
```

---

## Quy trình Node mới join cluster

```
1. Node k8s-worker2 join cluster
        ↓
2. flanneld khởi động trên worker2
        ↓
3. flanneld đọc podCIDR của node từ K8s API:
   kubectl get node k8s-worker2 -o jsonpath='{.spec.podCIDR}'
   → 10.244.2.0/24
        ↓
4. flanneld đăng ký vào K8s API:
   Node annotation: flannel.alpha.coreos.com/public-ip = 192.168.64.12
        ↓
5. flanneld tạo VTEP interface (flannel.1) với IP 10.244.2.0
        ↓
6. flanneld viết /run/flannel/subnet.env:
   FLANNEL_NETWORK=10.244.0.0/16
   FLANNEL_SUBNET=10.244.2.1/24
   FLANNEL_MTU=1450
   FLANNEL_IPMASQ=true
        ↓
7. flanneld trên các Node khác watch API → cập nhật FDB/ARP/routes
```

---

<!-- _class: lab -->

## Lab: Xem subnet allocation trong K8s API

```bash
multipass shell k8s-master

# Xem podCIDR được assign cho mỗi Node (thay thế etcd)
kubectl get nodes -o custom-columns=\
  'NAME:.metadata.name,PODCIDR:.spec.podCIDR,IP:.status.addresses[0].address'
# NAME          PODCIDR          IP
# k8s-master    10.244.0.0/24    192.168.64.10
# k8s-worker1   10.244.1.0/24    192.168.64.11
# k8s-worker2   10.244.2.0/24    192.168.64.12

# Xem annotation của Node (flanneld ghi public IP)
kubectl get node k8s-worker1 -o jsonpath='{.metadata.annotations}' | python3 -m json.tool
# {
#   "flannel.alpha.coreos.com/backend-data": "{\"VNI\":1,\"VtepMAC\":\"xx:xx:xx\"}",
#   "flannel.alpha.coreos.com/backend-type": "vxlan",
#   "flannel.alpha.coreos.com/kube-subnet-manager": "true",
#   "flannel.alpha.coreos.com/public-ip": "192.168.64.11"
# }
```

---

## Lab: Xem subnet.env và FDB table

```bash
# SSH vào worker1
multipass shell k8s-worker1

# File subnet.env mà CNI plugin đọc để biết range
cat /run/flannel/subnet.env
# FLANNEL_NETWORK=10.244.0.0/16
# FLANNEL_SUBNET=10.244.1.1/24
# FLANNEL_MTU=1450
# FLANNEL_IPMASQ=true

# FDB table: mapping VTEP MAC → Node IP
bridge fdb show dev flannel.1
# xx:xx:xx:xx:xx:xx dst 192.168.64.10 self permanent  ← master node
# yy:yy:yy:yy:yy:yy dst 192.168.64.12 self permanent  ← worker2

# ARP table của flannel.1 (inner IP → VTEP MAC)
ip neigh show dev flannel.1
# 10.244.0.0 lladdr xx:xx:xx:xx:xx:xx PERMANENT  ← gateway của master subnet
# 10.244.2.0 lladdr yy:yy:yy:yy:yy:yy PERMANENT  ← gateway của worker2 subnet
```

---

## Lab: Quan sát flanneld cập nhật khi thêm Node

```bash
# Quan sát log của flanneld khi có thay đổi
kubectl -n kube-flannel logs -f daemonset/kube-flannel-ds --since=1m

# Trên master, simulate Node annotation change
kubectl annotate node k8s-worker2 \
  flannel.alpha.coreos.com/public-ip=192.168.64.12 --overwrite

# Log sẽ thấy: "Handling add subnet event..."
# → flanneld tự động cập nhật FDB + ARP + routes

# Kiểm tra route mới
ip route show | grep 10.244.2
# 10.244.2.0/24 via 10.244.2.0 dev flannel.1
```

---

## Key Takeaways

**Phân công trách nhiệm:**

| Component | Trách nhiệm |
| :--- | :--- |
| **K8s API** | Lưu podCIDR allocation, Node annotations |
| **flanneld** | Watch API, cấu hình VTEP/FDB/routes, ghi subnet.env |
| **CNI plugin** | Đọc subnet.env, gán IP cho Pod từ range đó |

**Files quan trọng:**
```
/run/flannel/subnet.env          ← flanneld → CNI plugin
/etc/cni/net.d/10-flannel.conflist  ← CNI config
/opt/cni/bin/flannel             ← CNI plugin binary
```

**Debug commands:**
```bash
bridge fdb show dev flannel.1     # VTEP MAC mapping
ip neigh show dev flannel.1       # ARP inner IPs
kubectl get node -o json | jq '.items[].metadata.annotations'
```

> **Tập tiếp theo:** VXLAN encapsulation — tcpdump soi packet thực tế!
