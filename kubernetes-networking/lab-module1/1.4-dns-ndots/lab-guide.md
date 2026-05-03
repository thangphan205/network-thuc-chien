# Lab 1.4: Bắt DNS Query & Triển khai NodeLocal DNSCache

## 🎯 Mục tiêu
- Quan sát CoreDNS Corefile và cấu trúc DNS nội bộ K8s.
- Dùng `tcpdump` để bắt trực tiếp "thuế ndots:5" — đếm query thừa.
- Demo Headless Service: DNS trả về Pod IP thay vì ClusterIP.
- Fix ndots và deploy NodeLocal DNSCache.

---

## 🔬 Bước 0: Chuẩn bị Cluster

### Trường hợp A — Cluster còn từ Lab trước (chưa xóa)

```bash
vagrant status        # Vagrant
multipass list        # Multipass
```

Nếu VMs đang `stopped`:
```bash
vagrant up                                    # Vagrant
multipass start controlplane worker1 worker2  # Multipass
```

SSH vào controlplane và xác nhận:
```bash
vagrant ssh controlplane       # Vagrant
multipass shell controlplane   # Multipass
```

```bash
kubectl get nodes
# Cả 3 nodes Ready → bỏ qua phần B, đi thẳng Bước 1
```

---

### Trường hợp B — Cluster đã bị xóa (làm lại từ đầu)

**B1 — Tạo lại 3 VMs:**

```bash
# Vagrant — chạy từ thư mục lab-module0/
vagrant up

# Multipass — chạy từ thư mục lab-module0/
chmod +x setup-macos-multipass.sh && ./setup-macos-multipass.sh
```

**B2 — Init Control Plane:**

```bash
vagrant ssh controlplane       # Vagrant
multipass shell controlplane   # Multipass
```

```bash
sudo kubeadm init --apiserver-advertise-address=192.168.56.10 --pod-network-cidr=10.244.0.0/16  # Vagrant
sudo kubeadm init --pod-network-cidr=10.244.0.0/16                                               # Multipass

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**Copy lại lệnh `kubeadm join`** ở cuối output.

**B3 — Cài Flannel CNI:**

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl get nodes -w
```

**B4 — Join Workers** (2 terminal mới):

```bash
vagrant ssh worker1 && sudo kubeadm join <địa_chỉ_từ_B2>   # Vagrant worker1
vagrant ssh worker2 && sudo kubeadm join <địa_chỉ_từ_B2>   # Vagrant worker2
# hoặc multipass shell worker1 / worker2
```

**B5 — Verify:**

```bash
kubectl get nodes -o wide   # Cả 3 nodes phải Ready
```

---

## 🔬 Bước 1: Khám phá CoreDNS

> **Mục đích:** Hiểu CoreDNS là gì và cách nó được cấu hình trước khi thực hành DNS queries.

```bash
# CoreDNS chạy là Deployment trong kube-system
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
# → 2 coreDNS pod trên controlplane

# ClusterIP của CoreDNS — đây là nameserver trong resolv.conf của Pod
kubectl get svc kube-dns -n kube-system
# NAME       TYPE        CLUSTER-IP   PORT(S)
# kube-dns   ClusterIP   10.96.0.10   53/UDP,53/TCP

# Xem Corefile — cấu hình CoreDNS
kubectl get cm coredns -n kube-system -o yaml
# → Thấy: zone "cluster.local" (K8s internal), forward "." đến upstream DNS
# → Upstream thường là /etc/resolv.conf của Node hoặc 8.8.8.8
```

---

## 🔬 Bước 2: Quan sát resolv.conf trong Pod

> **Mục đích:** Thấy trực tiếp cấu hình `ndots:5` và search domains bên trong Pod.

```bash
# Tạo Pod debug
kubectl run debug-dns --image=nicolaka/netshoot --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/debug-dns --timeout=60s

# Xem resolv.conf
kubectl exec debug-dns -- cat /etc/resolv.conf
# nameserver 10.96.0.10
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5

# Giải thích:
# nameserver → ClusterIP của CoreDNS
# search     → Danh sách domain suffix thử khi query ngắn
# ndots:5    → Nếu domain có < 5 dấu chấm → thử search domains trước
```

---

## 🔬 Bước 3: Demo short name resolution qua search domain

> **Mục đích:** Thấy search domain hoạt động cho internal Service — đây là lý do short name như `web-svc` work.

```bash
# Tạo Service thử nghiệm
kubectl create deployment web --image=nginx --replicas=1
kubectl expose deployment web --port=80 --name=web-svc

# Test short name từ trong cùng namespace
kubectl exec debug-dns -- nslookup web-svc
# → Resolve thành công qua: web-svc.default.svc.cluster.local

# Test cross-namespace (cần FQDN)
kubectl exec debug-dns -- nslookup web-svc.default.svc.cluster.local
# → Cùng kết quả nhưng FQDN rõ ràng hơn

# ⚠️ dig mặc định KHÔNG dùng search domain → NXDOMAIN với short name
kubectl exec debug-dns -- dig web-svc
# → NXDOMAIN — dig query "web-svc." trực tiếp, không append search domain

# Fix: dùng +search hoặc FQDN
kubectl exec debug-dns -- dig +search web-svc          # dùng search domain
kubectl exec debug-dns -- dig web-svc.default.svc.cluster.local  # FQDN trực tiếp

# Dọn dẹp
kubectl delete deployment web
kubectl delete svc web-svc
```

---

## 🔬 Bước 4: Demo Headless Service — DNS trả về Pod IP

> **Mục đích:** Headless Service (`clusterIP: None`) khác ClusterIP Service: DNS không trả về 1 IP ảo mà trả về danh sách IP Pod thực. Dùng cho StatefulSet, Kafka, Cassandra — khi client cần kết nối trực tiếp đến từng Pod.

```bash
# Tạo Headless Service
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: headless-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: headless-demo
  template:
    metadata:
      labels:
        app: headless-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
---
apiVersion: v1
kind: Service
metadata:
  name: headless-svc
spec:
  clusterIP: None          # ← Headless
  selector:
    app: headless-demo
  ports:
  - port: 80
---
apiVersion: v1
kind: Service
metadata:
  name: clusterip-svc
spec:
  selector:
    app: headless-demo
  ports:
  - port: 80
EOF

kubectl wait --for=condition=Ready pod -l app=headless-demo --timeout=60s

# So sánh DNS response
kubectl exec debug-dns -- nslookup headless-svc
# → Nhiều A records — mỗi record = 1 Pod IP (3 pods = 3 IPs)

kubectl exec debug-dns -- nslookup clusterip-svc
# → 1 A record duy nhất = ClusterIP (IP ảo)

# Kết luận: Headless = client tự chọn Pod, ClusterIP = kube-proxy phân phối
kubectl delete deployment headless-demo
kubectl delete svc headless-svc clusterip-svc
```

---

## 🔬 Bước 5: Bắt DNS query — quan sát thuế ndots:5

> **Mục đích:** Nhìn thấy bằng mắt 3 query thừa khi truy cập domain bên ngoài.

```bash
# Terminal 1: SSH vào worker1, bắt gói DNS
vagrant ssh worker1    # hoặc: multipass shell worker1
sudo tcpdump -i any -nn 'udp port 53' -l
```

```bash
# Terminal 2: Từ Pod, query domain ngoài
kubectl exec debug-dns -- nslookup google.com
```

**Quan sát trong terminal 1 — đếm queries:**
```
# Query 1: google.com.default.svc.cluster.local  → NXDOMAIN (K8s search, thừa)
# Query 2: google.com.svc.cluster.local          → NXDOMAIN (K8s search, thừa)
# Query 3: google.com.cluster.local              → NXDOMAIN (K8s search, thừa)
# Query 4: google.com.lan                        → NXDOMAIN (.lan từ Vagrant DHCP, thừa)
# Query 5: google.com.                           → Answer 142.250.x.x ✅
# Query 6: google.com.          AAAA             → IPv6 answer ✅

# Tổng: 4 query thừa trong môi trường Vagrant (vì DHCP thêm search domain .lan)
# Production với static IP: chỉ 3 query thừa (không có .lan)
# Quy tắc: số query thừa = số search domain sau từ khóa "search" trong /etc/resolv.conf của Pod
```

**Demo: FQDN dấu chấm cuối — tránh 3 query thừa:**

```bash
# Thêm dấu chấm cuối = FQDN → query thẳng, không thử search domain
kubectl exec debug-dns -- nslookup google.com.
# → Chỉ 1 query duy nhất, không thử search domains
```

---

## 🔬 Bước 6: Fix ndots — giảm query thừa

```bash
# ⚠️ ndots:2 KHÔNG giúp được với google.com!
# google.com có 1 dấu chấm → 1 < 2 → vẫn thử search domain trước
# Cần ndots:1 để external domain (≥1 dấu chấm) query thẳng

# Tạo Pod với ndots:1
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: debug-ndots2
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
  dnsConfig:
    options:
    - name: ndots
      value: "1"
EOF

kubectl wait --for=condition=Ready pod/debug-ndots2 --timeout=60s

# Verify cấu hình
kubectl exec debug-ndots2 -- cat /etc/resolv.conf
# → options ndots:1

# Lặp lại tcpdump và query google.com
kubectl exec debug-ndots2 -- nslookup google.com
# → Chỉ 1 query: google.com. → Answer (1 dấu chấm, không < 1 → query thẳng)

# K8s service discovery vẫn hoạt động (bare hostname có 0 dấu chấm < 1)
kubectl exec debug-ndots2 -- nslookup kubernetes
# → kubernetes.default.svc.cluster.local (search domain vẫn được dùng)
```

---

## 🔬 Bước 7: Triển khai NodeLocal DNSCache

> **Mục đích:** Cache DNS ngay trên Node — giảm latency và tải cho CoreDNS.

```bash
# Download manifest với versioned URL
K8S_VERSION=$(kubectl version -o json | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['serverVersion']['gitVersion'])")
echo "K8s version: $K8S_VERSION"

curl -Lo nodelocaldns.yaml \
  "https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml"

# Lấy ClusterIP của kube-dns
KUBEDNS=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
echo "CoreDNS ClusterIP: $KUBEDNS"

# Thay thế placeholders
sed -i "s/__PILLAR__DNS__SERVER__/${KUBEDNS}/g" nodelocaldns.yaml
sed -i "s/__PILLAR__LOCAL__DNS__/169.254.20.10/g" nodelocaldns.yaml
sed -i "s/__PILLAR__DNS__DOMAIN__/cluster.local/g" nodelocaldns.yaml

# Deploy
kubectl apply -f nodelocaldns.yaml

# Chờ DaemonSet sẵn sàng trên tất cả Nodes
kubectl rollout status daemonset node-local-dns -n kube-system
kubectl get pods -n kube-system -l k8s-app=node-local-dns -o wide
```

---

## 🔬 Bước 8: Kiểm tra NodeLocal DNSCache hoạt động

```bash
# Trên Node — kiểm tra interface nodelocaldns
vagrant ssh worker1    # hoặc: multipass shell worker1
ip addr show nodelocaldns
# inet 169.254.20.10/32 scope global nodelocaldns   ← canonical IP
# inet 10.96.0.10/32   scope global nodelocaldns   ← kube-dns ClusterIP (transparent intercept)
```

> **Tại sao có 2 IP trên cùng 1 interface?** NodeLocal DNSCache dùng mode **transparent intercept**:
> - Bind `10.96.0.10` (kube-dns ClusterIP) để **chặn** query từ Pod trước khi ra khỏi Node
> - Pod vẫn thấy `nameserver 10.96.0.10` trong `/etc/resolv.conf` — **đây là expected behavior**
> - iptables `NOTRACK` rule redirect query đến `10.96.0.10` về local daemon thay vì forward qua network đến CoreDNS pod

```bash
# Verify iptables NOTRACK rule — dấu hiệu NodeLocal DNS đang intercept
sudo iptables -t raw -L OUTPUT -n | grep "169.254.20.10"
sudo iptables -t raw -L PREROUTING -n | grep "169.254.20.10"
# → Có rule NOTRACK = NodeLocal DNS active

# Pod resolv.conf vẫn có nameserver 10.96.0.10 — BÌNH THƯỜNG, không phải lỗi
kubectl run debug-after --image=nicolaka/netshoot --restart=Never -- sleep 600
kubectl wait --for=condition=Ready pod/debug-after --timeout=60s
kubectl exec debug-after -- cat /etc/resolv.conf
# nameserver 10.96.0.10   ← vẫn là CoreDNS ClusterIP, nhưng query được intercept local

# Verify query vẫn resolve được (qua local cache, không hop mạng)
kubectl exec debug-after -- nslookup kubernetes.default
# → Answer trả về bình thường

# Xem log NodeLocal DNS để confirm đang serve queries
kubectl logs -n kube-system -l k8s-app=node-local-dns --tail=20
```

---

## 📚 Kiến thức học được

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **CoreDNS** | Deployment trong kube-system, ánh xạ `svc.namespace.svc.cluster.local` → ClusterIP |
| **Headless Service** | `clusterIP: None` — DNS trả về Pod IP trực tiếp, dùng cho StatefulSet |
| **ndots:5** | Domain < 5 dấu chấm → thử 3 search domains trước → 3 query thừa |
| **FQDN trailing dot** | `google.com.` → query thẳng, bỏ qua search domain |
| **NodeLocal DNSCache** | Cache tại `169.254.20.10` trên mỗi Node, giảm latency và tải CoreDNS |

---

## ✅ Câu hỏi kiểm tra

1. Với `ndots:5`, query `github.com` gửi bao nhiêu DNS query? Ghi rõ từng query.
2. Headless Service khác ClusterIP Service ở điểm gì trong DNS response?
3. NodeLocal DNSCache dùng IP `169.254.20.10` — đây là loại IP gì? Tại sao không bao giờ bị conflict?
4. Cache miss thì NodeLocal DNSCache forward query đến đâu?
5. Tại sao `google.com.` (có dấu chấm cuối) chỉ cần 1 DNS query?

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod debug-dns debug-ndots2 debug-after --ignore-not-found
# Giữ NodeLocal DNSCache cho các Lab sau
```
