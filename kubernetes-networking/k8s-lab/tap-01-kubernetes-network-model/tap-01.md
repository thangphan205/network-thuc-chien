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

<br />
<br />

# Tập 1 - Kubernetes Network Model

## 4 nguyên tắc không NAT 

**Phần 0 — Nền tảng K8s Networking** · `#NetworkModel` `#CNI` `#routing`
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## Mục tiêu tập này

Sau tập 1, bạn sẽ:

- Phát biểu đúng 4 nguyên tắc K8s networking không cần nhìn tài liệu
- Giải thích tại sao "không NAT" lại khó hơn "có NAT"
- Quan sát trạng thái `NotReady` khi cluster chưa có CNI
- Hiểu tại sao CNI tồn tại và vai trò của nó

**Prerequisites:** Đã cài Multipass + tạo 3 VM Ubuntu 26.04 theo `../tap-00-setup-lab/lab-guide.md`

---

## Kubernetes không tự cài mạng

K8s chỉ đặt ra **hợp đồng** — ai muốn làm CNI thì phải đảm bảo 4 điều:

```
Nguyên tắc 1: Pod-to-Pod không NAT (dù khác Node)
──────────────────────────────────────────────────
Pod A IP: 10.244.1.5  →  Pod B IP: 10.244.2.7
Không qua NAT, không đổi IP nguồn

Nguyên tắc 2: Node-to-Pod không NAT
──────────────────────────────────────────────────
Worker node IP: 192.168.64.11  →  Pod IP: 10.244.2.7
Thẳng đến Pod, không masquerade

Nguyên tắc 3: Pod thấy đúng IP nguồn của caller
──────────────────────────────────────────────────
Pod B nhận request: src_ip = 10.244.1.5 (IP thật của Pod A)
Không bị "đổi" thành IP Node

Nguyên tắc 4: Pod IP unique toàn cluster
──────────────────────────────────────────────────
Không có 2 Pod nào cùng IP, dù ở Node khác nhau
```

---

## Tại sao "không NAT" lại khó?

**Mạng thông thường (có NAT):**
```
Pod A (10.244.1.5)
   ↓
Node 1 eth0 (192.168.64.10)  ← NAT: đổi src thành IP Node
   ↓ qua switch/router
Node 2 eth0 (192.168.64.11)
   ↓ de-NAT
Pod B (10.244.2.7)
```
Đơn giản vì Router không cần biết Pod IP tồn tại.

**K8s yêu cầu:**
```
Pod A (10.244.1.5) → ... → Pod B thấy src = 10.244.1.5
```
Router phải biết `10.244.1.5` ở đâu → cần routing hoặc encapsulation → **đây là bài toán CNI giải**.

---

## Hậu quả khi không có CNI

```bash
# Quan sát trạng thái cluster chưa cài CNI
multipass exec k8s-master -- kubectl get nodes
# NAME          STATUS     ROLES           AGE
# k8s-master    NotReady   control-plane   3m
# k8s-worker1   NotReady   <none>          90s
# k8s-worker2   NotReady   <none>          85s
```

**Tại sao NotReady?**
```bash
multipass exec k8s-master -- kubectl describe node k8s-master | grep -A5 Conditions
# NetworkPlugin is not installed — kubelet đang chờ CNI plugin

# Thử tạo Pod
multipass exec k8s-master -- kubectl run test --image=nginx
multipass exec k8s-master -- kubectl get pod test
# NAME   READY   STATUS    AGE
# test   0/1     Pending   30s  ← Không schedule được vì Node NotReady
```

---

<!-- _class: lab -->

## Lab: Tạo cluster & quan sát network namespace

```bash
# SSH vào master
multipass shell k8s-master

# Kiểm tra network interfaces hiện tại (chưa có CNI)
ip link show
# 1: lo: <LOOPBACK,UP,LOWER_UP>
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>   ← IP thật của VM
# (Không có cni0, flannel.1, cilium_host... vì chưa cài CNI)

# Kiểm tra routing table
ip route show
# default via 192.168.64.1 dev eth0
# 192.168.64.0/24 dev eth0
# (Không có route đến 10.244.x.x vì chưa có CNI)

# Xem kubelet log - thấy CNI error
sudo journalctl -u kubelet --since "5 min ago" | grep -i "cni\|network"
# Error: network plugin is not ready: cni config uninitialized
# Error: failed to find plugin "flannel" in path [/opt/cni/bin]
```

---

## Lab: Network namespace của container chờ CNI

```bash
# Cài Flannel để nodes Ready (tập sau sẽ giải thích chi tiết)
kubectl apply -f \
  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Theo dõi quá trình CNI được cài
watch kubectl get nodes
# Sau ~30 giây:
# NAME          STATUS   ROLES           AGE
# k8s-master    Ready    control-plane   5m   ← Ready!
# k8s-worker1   Ready    <none>          4m
# k8s-worker2   Ready    <none>          4m

# Xem interface mới xuất hiện sau khi Flannel cài
ip link show
# ...
# 3: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP>  ← CNI tạo ra
# 4: cni0: <BROADCAST,MULTICAST,UP,LOWER_UP>       ← Bridge cho Pods

# Xem routes mới
ip route show
# 10.244.0.0/24 dev cni0  ← Pod subnet của node này
# 10.244.1.0/24 via 10.244.1.0 dev flannel.1  ← Route đến worker1
# 10.244.2.0/24 via 10.244.2.0 dev flannel.1  ← Route đến worker2
```

---

## Key Takeaways

**4 nguyên tắc K8s networking:**

| # | Nguyên tắc | Ý nghĩa |
| :--- | :--- | :--- |
| 1 | Pod-to-Pod không NAT | IP nguồn giữ nguyên qua các Node |
| 2 | Node-to-Pod không NAT | Node access thẳng Pod IP |
| 3 | Pod thấy đúng IP caller | Không masquerade |
| 4 | Pod IP unique toàn cluster | Không conflict dù khác Node |

**Bài học từ lab:**
- Cluster không có CNI → Node `NotReady` → Pod `Pending`
- CNI tạo ra interfaces (`flannel.1`, `cni0`) và routes sau khi cài
- Routes `10.244.x.0/24` là bằng chứng CNI đang hoạt động

> **Tập tiếp theo:** Ai tạo ra `cni0` bridge? Pause container ở đâu? veth pair là gì?
