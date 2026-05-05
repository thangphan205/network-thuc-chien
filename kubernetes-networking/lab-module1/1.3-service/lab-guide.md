# Lab 1.3: Phân tích Kiến trúc Service, Headless, iptables, IPVS & nftables

## 🎯 Mục tiêu
- Thực chứng hoạt động của Control Plane (EndpointSlice) và CoreDNS (Headless Service).
- Phân tích chain iptables được Data Plane (Kube-proxy) sinh ra tự động.
- Chuyển kube-proxy sang IPVS mode và kiểm tra bảng routing O(1).
- Thử nghiệm đánh chặn và giữ Source IP thật với `externalTrafficPolicy: Local`.

---

## 🗺️ Topology Diagram

**Headless Service — DNS trả thẳng IP Pod (Không qua Kube-proxy):**
```
Client (Trong Cluster)
  │  nslookup web-headless
  ▼
CoreDNS ──► Trả về danh sách [Pod1 IP, Pod2 IP, Pod3 IP]
  │
  ▼ Client chọn và kết nối TRỰC TIẾP tới Pod IP (Bỏ qua Data Plane VIP)
```

**iptables mode — ClusterIP data flow:**
```
Client (Trong Cluster)
    │  dst: ClusterIP 10.96.X.X:80
    ▼
iptables nat table (Kube-proxy lập trình)
    │
    ├─► KUBE-SERVICES  (match dst=ClusterIP)
    │       │
    │       ▼
    │   KUBE-SVC-XXXX  (load balance: statistic --probability)
    │       │
    │       ├─ 33% ──► KUBE-SEP-AAA ──► DNAT → Pod1 10.244.1.X:80
    │       ├─ 33% ──► KUBE-SEP-BBB ──► DNAT → Pod2 10.244.2.X:80
    │       └─ 33% ──► KUBE-SEP-CCC ──► DNAT → Pod3 10.244.1.Y:80
```

**IPVS mode — so sánh:**
```
Client
    │  dst: ClusterIP 10.96.X.X:80
    ▼
kube-ipvs0 (dummy interface, trạng thái DOWN là bình thường)
    │  IPVS kernel hash table O(1)
    ▼
Virtual Server: 10.96.X.X:80  algo=rr
    ├──► Real Server: Pod1 10.244.1.X:80  weight=1
    ├──► Real Server: Pod2 10.244.2.X:80  weight=1
    └──► Real Server: Pod3 10.244.1.Y:80  weight=1
```

---

## 🔬 Bước 0: Chuẩn bị Cluster

### Trường hợp A — Cluster còn từ Lab trước (chưa xóa)

Kiểm tra nhanh:
```bash
vagrant status        # Vagrant
multipass list        # Multipass
```

Nếu VMs đang `stopped` thì bật lại:
```bash
vagrant up                                    # Vagrant
multipass start controlplane worker1 worker2  # Multipass
```

SSH vào controlplane và xác nhận cluster:
```bash
vagrant ssh controlplane       # Vagrant
multipass shell controlplane   # Multipass

kubectl get nodes
# Cả 3 nodes phải Ready → bỏ qua phần B, đi thẳng Bước 1
```

### Trường hợp B — Cluster đã bị xóa (làm lại từ đầu)

(Vui lòng thực hiện lại Bước B1 tới B5 từ Lab 1.2 trước đây để tạo cụm kubeadm 1 Control Plane và 2 Worker).

---

## 🔬 Bước 1: Khảo sát Headless Service & DNS

> **Mục đích:** Hiểu rằng Service không chỉ là Data Plane (Kube-proxy). Với Headless Service, Data Plane đứng ngoài cuộc, CoreDNS đóng vai trò điều hướng bằng cách trả thẳng IP của các Pod khoẻ mạnh.

**1. Tạo workload Deployment**
```bash
kubectl create deployment web --image=nginx --replicas=3
kubectl rollout status deployment web
```

**2. Tạo Headless Service (đặc trưng là `clusterIP: None`)**
```bash
kubectl expose deployment web --port=80 --name=web-headless --cluster-ip=None
```

**3. Chứng minh CoreDNS phân giải trực tiếp**
```bash
# Chạy Pod tạm để dùng công cụ nslookup
kubectl run dns-test --image=infoblox/dnstools --rm -it --restart=Never -- sh

# (Bên trong Pod dns-test)
dnsq a web-headless.default.svc.cluster.local
```
*Kết quả:* DNS sẽ trả về danh sách 3 bản ghi `A`, tương ứng với 3 địa chỉ IP của 3 Pod `nginx`. Gõ `exit` để thoát Pod.

**4. Chứng minh Kube-proxy "Bỏ qua" Headless Service**
```bash
# Mở một terminal khác, SSH vào Worker Node (ví dụ worker1)
vagrant ssh worker1

# Kiểm tra bảng iptables
sudo iptables -t nat -L KUBE-SERVICES -n | grep "web-headless"
```
*Kết quả:* KHÔNG CÓ KẾT QUẢ. Kube-proxy không tạo rules VIP cho Headless Service.

---

## 🔬 Bước 2: Tạo Service ClusterIP và xem EndpointSlice

> **Mục đích:** Khi có VIP, Kube-proxy sẽ lập trình Kernel. Xem đối tượng `EndpointSlice` thay thế cho `Endpoints` cũ.

```bash
# Tạo ClusterIP Service cho nhóm 'web'
kubectl expose deployment web --port=80 --name=web-svc

# Lấy ClusterIP
kubectl get svc web-svc
# Ghi nhớ IP này (ví dụ: 10.96.XX.XX)
```

**Quan sát Control Plane tạo EndpointSlice (v1.33+):**
```bash
kubectl get endpointslice -l kubernetes.io/service-name=web-svc
# NAME             ADDRESSTYPE   PORTS   ENDPOINTS
# web-svc-xxxxx   IPv4          80      10.244.X.X,10.244.X.Y,...

# Mô tả để xem chi tiết
kubectl describe endpointslice -l kubernetes.io/service-name=web-svc
```

---

## 🔬 Bước 3: Phân tích iptables chains trên Node

> **Mục đích:** Hiểu thuật toán Load Balancing xác suất của Kube-proxy iptables.
> - **KUBE-SERVICES** — chain điểm vào
> - **KUBE-SVC-xxx** — chain load balancer ngẫu nhiên
> - **KUBE-SEP-xxx** — chain DNAT tới Pod

```bash
# SSH vào Worker Node (nếu chưa vào)
vagrant ssh worker1

# Lấy lại ClusterIP trên worker node (biến $SVC_IP từ bước trước chỉ tồn tại trên controlplane)
SVC_IP=$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')
sudo iptables -t nat -L KUBE-SERVICES -n | grep $SVC_IP

# Xem chain load balancer — 3 rules với probability
KUBE_SVC=$(sudo iptables -t nat -S KUBE-SERVICES | grep $SVC_IP | grep -oP 'KUBE-SVC-\w+' | head -1)
sudo iptables -t nat -L $KUBE_SVC -n -v
# Bạn sẽ thấy statistic --mode random --probability 0.33333
# và probability 0.50000

# KUBE-SEP nằm trong KUBE-SVC chain (không phải KUBE-SERVICES)
# Lấy tên 1 chain KUBE-SEP từ output trên rồi xem rule DNAT
KUBE_SEP=$(sudo iptables -t nat -S $KUBE_SVC | grep -oP 'KUBE-SEP-\w+' | head -1)
sudo iptables -t nat -L $KUBE_SEP -n -v
# Bạn sẽ thấy rule DNAT: --to-destination <Pod IP>:<port>
```

---

## 🔬 Bước 4: Chuyển sang IPVS mode

> **Mục đích:** IPVS dùng `Hash Table` cấu trúc O(1) tối ưu hiệu năng. Interface `kube-ipvs0` sẽ được tạo để nhận packet.

```bash
# Trở về Control Plane terminal
# Load kernel module
sudo modprobe ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack

# Cấu hình kube-proxy qua ConfigMap
kubectl edit configmap kube-proxy -n kube-system
# Tìm `mode: ""` và sửa thành `mode: "ipvs"`

# Restart lại các daemon pod để áp dụng
kubectl rollout restart daemonset kube-proxy -n kube-system
kubectl rollout status daemonset kube-proxy -n kube-system

# Cách kiểm tra: interface kube-ipvs0 đã xuất hiện (State DOWN là bình thường)
ip link show kube-ipvs0
```

---

## 🔬 Bước 5: Kiểm tra bảng IPVS

```bash
# SSH vào Worker Node
vagrant ssh worker1

# Cài đặt ipvsadm
sudo apt install -y ipvsadm

# Xem cấu trúc tra cứu IPVS (Virtual Server tới Real Server)
sudo ipvsadm -Ln
# TCP  10.96.XX.XX:80 rr         ← Virtual server = ClusterIP
#   -> 10.244.0.X:80  Masq  1    ← Real server = Pod IP

# So sánh bảng iptables KUBE-SERVICES (Không còn rules routing do nhường quyền cho IPVS)
sudo iptables -t nat -L KUBE-SERVICES -n | grep $SVC_IP
```

---

## 🔬 Bước 6: Thử nghiệm externalTrafficPolicy

> **Mục đích:** Hiểu vì sao mặc định khi dùng NodePort bạn không thấy được IP công cộng của người dùng, và cách sửa chữa.
>
> ⚠️ **Lưu ý quan trọng:** `externalTrafficPolicy` chỉ có tác dụng với traffic đến từ **bên ngoài cluster** (external client). Nếu curl từ bên trong cluster (controlplane, pod) thì traffic được coi là internal và kết quả sẽ không phản ánh đúng hành vi. Hãy chạy lệnh `curl` từ **host machine** (máy tính của bạn, không phải VM).

```bash
# Trên Control Plane, đổi Service thành NodePort
kubectl expose deployment web --port=80 --type=NodePort --name=web-nodeport
NODEPORT=$(kubectl get svc web-nodeport -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes worker1 -o jsonpath='{.status.addresses[0].address}')

echo "NodePort: $NODE_IP:$NODEPORT"
```

```bash
# Chạy từ HOST MACHINE (terminal ngoài VM, không phải trong vagrant ssh)
curl -s http://<NODE_IP>:<NODEPORT} > /dev/null
```

```bash
# Quan sát Log của Nginx — bạn sẽ thấy IP nguồn là IP của Node (SNAT xảy ra)
# Ví dụ: 10.0.2.2 (IP của VirtualBox host adapter) hoặc IP internal node
kubectl logs -l app=web --tail=5
```

**Bật externalTrafficPolicy: Local**
```bash
# Cập nhật policy
kubectl patch svc web-nodeport -p '{"spec":{"externalTrafficPolicy":"Local"}}'

# Curl lại từ HOST MACHINE
curl -s http://<NODE_IP>:<NODEPORT> > /dev/null

# Log bây giờ sẽ hiện IP thật của host machine (không bị SNAT)
kubectl logs -l app=web --tail=5
```

> **Giải thích:** Với `Cluster` policy, Node nhận gói tin từ external client → SNAT source IP thành Node IP để có thể forward đến Pod trên node khác → Nginx chỉ thấy Node IP. Với `Local` policy, Node chỉ forward đến Pod **cùng node**, không cần SNAT → Nginx thấy IP thật của client.

---

## 🔬 Bước 7: Thử nghiệm SessionAffinity

> **Mục đích:** Thấy rõ Kube-proxy ghim kết nối theo Client IP — mọi request từ cùng 1 IP luôn route đến cùng 1 Pod.

```bash
# Trên Control Plane
# Bật SessionAffinity: ClientIP cho service web-svc
kubectl patch svc web-svc -p '{"spec":{"sessionAffinity":"ClientIP"}}'

# Xác nhận
kubectl get svc web-svc -o jsonpath='{.spec.sessionAffinity}'
# → ClientIP
```

**Chứng minh ghim session:**
```bash
# Lấy ClusterIP
SVC_IP=$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')

# Chạy Pod tạm trong cluster, curl nhiều lần
kubectl run affinity-test --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c "for i in \$(seq 1 10); do curl -s http://${SVC_IP}/etc/hostname; done"
# Kết quả: cùng 1 hostname (Pod name) lặp lại 10 lần → ghim session thành công
```

**So sánh không có SessionAffinity:**
```bash
# Tắt SessionAffinity
kubectl patch svc web-svc -p '{"spec":{"sessionAffinity":"None"}}'

kubectl run affinity-test --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c "for i in \$(seq 1 10); do curl -s http://${SVC_IP}/etc/hostname; done"
# Kết quả: hostname thay đổi ngẫu nhiên giữa các Pod → round-robin bình thường
```

---

## 🔬 Bước 8: Thử nghiệm nftables mode (K8s v1.33+)

> **Lưu ý:** Chỉ áp dụng nếu kernel >= 5.13. Ubuntu 22.04+ (Ví dụ Lab đang dùng) hỗ trợ hoàn toàn.

```bash
# Edit configmap đổi sang nftables
kubectl edit configmap kube-proxy -n kube-system
# mode: "nftables"

kubectl rollout restart daemonset kube-proxy -n kube-system

# (Trên Worker Node) Xem rule gom cụm siêu tốc
sudo apt install -y nftables
sudo nft list table ip kube-proxy
```

---

## 📚 Kiến thức học được

1. **Service Hierarchy**: Service chia làm Control Plane (quản lý EndpointSlice) và Data Plane (Kube-proxy).
2. **Headless Service**: Không sử dụng VIP, phụ thuộc trực tiếp vào CoreDNS để Load Balancing.
3. **EndpointSlice**: Bản nâng cấp từ `Endpoints` giải quyết vấn đề nghẽn cổ chai cụm khi workload lớn bằng cách chia nhỏ các batch 100 IPs.
4. **Data Plane Options**: `iptables` là cơ bản O(n), `IPVS` siêu tốc độ O(1), và `nftables` cập nhật atomic tiên tiến nhất hiện tại.
5. **externalTrafficPolicy Local**: Giữ Source IP thật với NodePort/LoadBalancer traffic, đánh đổi bằng phân tải không đều nếu Pod không rải đều trên Node.
6. **internalTrafficPolicy Local**: Route Pod-to-Pod traffic đến Pod cùng Node — giảm latency và cross-node bandwidth.
7. **SessionAffinity ClientIP**: Ghim kết nối theo IP client, đảm bảo request từ cùng 1 IP luôn đến cùng 1 Pod — phù hợp ứng dụng stateful.

---

## 🧹 Dọn dẹp

```bash
kubectl delete deployment web
kubectl delete svc web-svc web-nodeport web-headless
```
