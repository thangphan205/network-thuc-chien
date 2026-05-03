# Lab 1.3: Phân tích Kube-proxy iptables, IPVS & nftables

## 🎯 Mục tiêu
- Tạo Service và phân tích chain iptables được sinh ra tự động.
- Chuyển kube-proxy sang IPVS mode và kiểm tra bảng IPVS.
- Thử nghiệm `externalTrafficPolicy: Local`.

---

## 🗺️ Topology Diagram

**iptables mode — ClusterIP data flow:**
```
Client (Pod / Node)
    │  dst: ClusterIP 10.96.X.X:80
    ▼
iptables nat table
    │
    ├─► KUBE-SERVICES  (match dst=ClusterIP)
    │       │
    │       ▼
    │   KUBE-SVC-XXXX  (load balance: statistic --probability)
    │       │
    │       ├─ 33% ──► KUBE-SEP-AAA ──► DNAT → Pod1 10.244.1.X:80
    │       ├─ 33% ──► KUBE-SEP-BBB ──► DNAT → Pod2 10.244.2.X:80
    │       └─ 33% ──► KUBE-SEP-CCC ──► DNAT → Pod3 10.244.1.Y:80
    │
    └─► Packet đến Pod IP thực (sau DNAT)
```

**IPVS mode — so sánh:**
```
Client
    │  dst: ClusterIP 10.96.X.X:80
    ▼
kube-ipvs0 (dummy interface, state DOWN — bình thường)
    │  IPVS kernel hash table O(1)
    ▼
Virtual Server: 10.96.X.X:80  algo=rr
    ├──► Real Server: Pod1 10.244.1.X:80  weight=1
    ├──► Real Server: Pod2 10.244.2.X:80  weight=1
    └──► Real Server: Pod3 10.244.1.Y:80  weight=1
```

**externalTrafficPolicy: Cluster vs Local:**
```
External Client  ──►  NodePort :30080
                            │
               ┌────────────┴────────────┐
               │  Cluster (default)       │  Local
               │  SNAT → forward đến      │  Chỉ Pod trên Node này
               │  Pod bất kỳ (mất src IP) │  (giữ src IP thật)
               └──────────────────────────┘
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
```

```bash
kubectl get nodes
# Cả 3 nodes phải Ready → bỏ qua phần B, đi thẳng Bước 1
```

---

### Trường hợp B — Cluster đã bị xóa (làm lại từ đầu)

**B1 — Tạo lại 3 VMs:**

```bash
# Vagrant (Windows/Linux/macOS Intel) — chạy từ thư mục lab-module0/
vagrant up

# Multipass (macOS / Windows / Linux) — chạy từ thư mục lab-module0/
chmod +x setup-macos-multipass.sh
./setup-macos-multipass.sh
```

Chờ 3–10 phút. Kiểm tra:
```bash
vagrant status        # Vagrant
multipass list        # Multipass
```

**B2 — Init Control Plane:**

```bash
vagrant ssh controlplane       # Vagrant
multipass shell controlplane   # Multipass
```

```bash
# Vagrant (dùng IP tĩnh của interface host-only)
sudo kubeadm init --apiserver-advertise-address=192.168.56.10 --pod-network-cidr=10.244.0.0/16

# Multipass (dùng IP mặc định của VM)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**Copy lại lệnh `kubeadm join`** ở cuối output (cần cho bước B4).

**B3 — Cài Flannel CNI:**

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl get nodes -w   # chờ controlplane Ready
```

**B4 — Join Worker Nodes** (mở 2 terminal mới):

```bash
# Terminal 2 — worker1
vagrant ssh worker1        # hoặc: multipass shell worker1
sudo kubeadm join <địa_chỉ_từ_bước_B2>

# Terminal 3 — worker2
vagrant ssh worker2        # hoặc: multipass shell worker2
sudo kubeadm join <địa_chỉ_từ_bước_B2>
```

**B5 — Xác nhận cluster sẵn sàng:**

```bash
kubectl get nodes -o wide
# Cả 3 nodes phải ở trạng thái Ready
```

---

## 🔬 Bước 1: Tạo Deployment + Service ClusterIP

> **Mục đích:** Tạo workload để quan sát. kube-proxy watch API Server và ngay lập tức sinh iptables/IPVS rules khi Service được tạo.

```bash
# Tạo deployment với 3 replicas
kubectl create deployment web --image=nginx --replicas=3

# Chờ tất cả pods Running
kubectl rollout status deployment web
kubectl get pods -l app=web -o wide
# Ghi lại NODE và POD IP của từng pod — dùng để đối chiếu với KUBE-SEP

# Tạo ClusterIP Service
kubectl expose deployment web --port=80 --name=web-svc

# Lấy ClusterIP
kubectl get svc web-svc
# NAME      TYPE        CLUSTER-IP      PORT(S)
# web-svc   ClusterIP   10.96.XX.XX     80/TCP
```

**Verify — ClusterIP trả lời từ bên trong cluster:**

```bash
# Dùng pod tạm để curl ClusterIP (ClusterIP không accessible từ máy host)
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')
# → Nhận HTML response từ nginx
```

**Quan sát EndpointSlice — thay thế Endpoints từ K8s v1.33:**

> **Mục đích:** `Endpoints` cũ lưu toàn bộ Pod IP trong 1 object → nếu Service có 1000 pods, object đó rất lớn, mỗi lần Pod thay đổi phải ghi lại toàn bộ. `EndpointSlice` chia nhỏ tối đa 100 pods/slice → cập nhật chỉ ảnh hưởng 1 slice, không cả danh sách.

```bash
# Xem EndpointSlice của web-svc (K8s v1.33+ dùng EndpointSlice làm mặc định)
kubectl get endpointslice -l kubernetes.io/service-name=web-svc
# NAME             ADDRESSTYPE   PORTS   ENDPOINTS              AGE
# web-svc-xxxxx   IPv4          80      10.244.X.X,10.244.X.X,10.244.X.X

# Xem chi tiết — mỗi slice chứa tối đa 100 endpoints
kubectl describe endpointslice -l kubernetes.io/service-name=web-svc
# → Thấy IP của từng Pod, trạng thái Ready

# So sánh với Endpoints object cũ (vẫn tồn tại nhưng deprecated)
kubectl get endpoints web-svc
kubectl describe endpoints web-svc
# → Cùng danh sách IP, nhưng tất cả trong 1 object duy nhất

# Kube-proxy đọc EndpointSlice (không phải Endpoints) để lập trình rules
kubectl get endpointslice -A | head -20
# → Mỗi Service có 1 hoặc nhiều EndpointSlice
```

---

## 🔬 Bước 2: Phân tích iptables chains trên Node

> **Mục đích:** Hiểu cơ chế kube-proxy iptables mode. Mỗi Service tạo ra 3 loại chain:
> - **KUBE-SERVICES** — chain "điểm vào", match destination IP = ClusterIP → nhảy vào KUBE-SVC
> - **KUBE-SVC-xxx** — chain load balancer, dùng `statistic --probability` để phân tải đều giữa các Pod
> - **KUBE-SEP-xxx** — chain "Service Endpoint", DNAT packet → Pod IP:Port thực tế

```
Packet đến ClusterIP:80
    │
    ▼ KUBE-SERVICES (match dst=ClusterIP)
    │
    ▼ KUBE-SVC-xxx (load balance ngẫu nhiên)
       ├─ 33% → KUBE-SEP-aaa  → DNAT → Pod1 IP:80
       ├─ 50% → KUBE-SEP-bbb  → DNAT → Pod2 IP:80
       └─ 100%→ KUBE-SEP-ccc  → DNAT → Pod3 IP:80
```

> **Tại sao probability lại là 1/3, 1/2, 1?**
> Rule đầu: 33% hit → Pod1. Rule thứ 2: 50% của lượng còn lại (67%) = 33% → Pod2. Rule cuối: 100% của lượng còn lại = 33% → Pod3. Tổng 3 Pod mỗi Pod nhận đúng 1/3.

```bash
# SSH vào Worker Node
vagrant ssh worker1    # hoặc: multipass shell worker1

# Lấy tên chain KUBE-SVC của web-svc (chứa ClusterIP)
SVC_IP=$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}' 2>/dev/null || \
  sudo iptables -t nat -L KUBE-SERVICES -n | grep "web-svc" | awk '{print $4}' | cut -d: -f1)

# Xem rule điểm vào — KUBE-SERVICES
sudo iptables -t nat -L KUBE-SERVICES -n | grep -A2 "web-svc"
# → dport 80 → jump KUBE-SVC-xxxxxxxx

# Lấy tên chain KUBE-SVC
KUBE_SVC=$(sudo iptables -t nat -L KUBE-SERVICES -n | grep "web-svc" | grep -o 'KUBE-SVC-[A-Z0-9]*')
echo "Chain: $KUBE_SVC"

# Xem chain load balancer — 3 rules với probability
sudo iptables -t nat -L $KUBE_SVC -n -v
# pkts bytes target     prot  KUBE-SEP-aaa  statistic --mode random --probability 0.33333
# pkts bytes target     prot  KUBE-SEP-bbb  statistic --mode random --probability 0.50000
# pkts bytes target     prot  KUBE-SEP-ccc  (không có statistic = 100% fallthrough)

# Xem từng KUBE-SEP — điểm DNAT sang Pod IP
sudo iptables -t nat -L KUBE-SERVICES -n | grep "KUBE-SEP" | head -20
# Đối chiếu IP trong DNAT rule với output `kubectl get pods -o wide` ở Bước 1
```

**Verify — đếm packet đang đi qua rule:**

```bash
# Reset bộ đếm
sudo iptables -t nat -Z $KUBE_SVC

# Sinh traffic từ bên trong cluster
kubectl run curl-flood --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c 'for i in $(seq 1 30); do curl -s http://web-svc > /dev/null; done'

# Xem phân phối packet
sudo iptables -t nat -L $KUBE_SVC -n -v
# → pkts gần như đều nhau giữa 3 SEP
```

---

## 🔬 Bước 3: Chuyển sang IPVS mode

> **Mục đích:** So sánh IPVS vs iptables. iptables duyệt rule tuyến tính O(n) — 1000 Services = 1000 rules phải check. IPVS dùng hash table O(1) — không đổi khi có thêm Services. Quan trọng với cluster lớn (>500 Services).

```bash
# Trên Control Plane

# Cần load kernel module ipvs trước
sudo modprobe ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack

# Chỉnh kube-proxy ConfigMap
kubectl edit configmap kube-proxy -n kube-system
# Tìm dòng: mode: ""
# Sửa thành: mode: "ipvs"

# Restart kube-proxy DaemonSet
kubectl rollout restart daemonset kube-proxy -n kube-system
kubectl rollout status daemonset kube-proxy -n kube-system
# → daemonset.apps/kube-proxy successfully rolled out

# Xác nhận kube-proxy đã dùng IPVS

# Cách 1: Interface kube-ipvs0 — chỉ xuất hiện khi IPVS mode active
ip link show kube-ipvs0
# → Output ví dụ:
#   7: kube-ipvs0: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN ...
# → "state DOWN" là BÌNH THƯỜNG — kube-ipvs0 là dummy interface, không có
#   physical link nên kernel báo DOWN. Interface tồn tại = IPVS đang chạy.
#   kube-proxy bind ClusterIP lên interface này để kernel route traffic vào IPVS.
# → Không thấy interface kube-ipvs0 = vẫn đang iptables mode.

# Cách 2: ClusterIP được bind lên kube-ipvs0
ip addr show kube-ipvs0 | grep 10.96
# → Thấy ClusterIP của web-svc = kube-proxy đang dùng IPVS

# Cách 3: Xem config đang apply (nguồn chân lý)
kubectl get configmap kube-proxy -n kube-system -o jsonpath='{.data.config\.conf}' | grep mode
# → mode: ipvs

# Cách 4: Log của pod hiện tại (grep sau khi restart)
kubectl logs -n kube-system $(kubectl get pod -n kube-system -l k8s-app=kube-proxy -o name | head -1) | grep -i ipvs
# → "Using ipvs Proxier" — nếu trống thì chạy không có grep để xem toàn bộ log
```

---

## 🔬 Bước 4: Kiểm tra bảng IPVS

> **Mục đích:** Xem cấu trúc virtual server của IPVS — ClusterIP là "virtual server", mỗi Pod IP là "real server". IPVS xử lý load balancing trong kernel space, không cần duyệt iptables chain.

```bash
# SSH vào Worker Node
vagrant ssh worker1    # hoặc: multipass shell worker1

# Cài ipvsadm nếu chưa có
sudo apt install -y ipvsadm

# Xem bảng IPVS — virtual servers và real servers
sudo ipvsadm -Ln
# TCP  10.96.XX.XX:80 rr         ← Virtual server = ClusterIP, algo = round-robin
#   -> 10.244.0.X:80  Masq  1     ← Real server = Pod IP, weight=1
#   -> 10.244.1.X:80  Masq  1
#   -> 10.244.2.X:80  Masq  1

# So sánh với iptables: iptables KHÔNG còn có KUBE-SVC chains nữa
sudo iptables -t nat -L KUBE-SERVICES -n | grep "web-svc"
# → Chỉ còn rule chuyển hướng vào IPVS, không có KUBE-SVC-xxx

# Xem thống kê kết nối đến từng Pod
sudo ipvsadm -Ln --stats
# → Conns, InPkts, OutPkts, InBytes, OutBytes cho từng real server

# Xem active connections hiện tại
sudo ipvsadm -Lnc

# Thử đổi thuật toán LB — IPVS hỗ trợ nhiều algo hơn iptables
# rr=round-robin, lc=least-connection, dh=destination-hash, sh=source-hash
SVC_IP=$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')
sudo ipvsadm -E -t ${SVC_IP}:80 -s lc
# → Đổi sang least-connection — forward đến Pod có ít active connections nhất
sudo ipvsadm -Ln | grep -A4 "${SVC_IP}"
# → Thấy "lc" thay vì "rr"

# Khôi phục round-robin
sudo ipvsadm -E -t ${SVC_IP}:80 -s rr
```

**Verify — ClusterIP vẫn hoạt động sau khi chuyển mode:**

```bash
kubectl run curl-test2 --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')
# → Vẫn nhận HTML response — load balancing vẫn chạy, chỉ đổi cơ chế
```

---

## 🔬 Bước 5: Thử nghiệm externalTrafficPolicy

> **Mục đích:** Hiểu vấn đề Source IP với NodePort. Policy mặc định `Cluster`: traffic đến bất kỳ Node nào đều được forward đến Pod bất kỳ (kể cả Pod trên Node khác) → Node thực hiện SNAT để đảm bảo reply về đúng — mất Source IP thật. Policy `Local`: chỉ forward đến Pod trên chính Node đó nhận traffic → không cần SNAT → giữ Source IP thật.
>
> **Use case thực tế:** WAF, rate-limiting theo IP, access log audit — tất cả cần IP thật của client. Dùng `externalTrafficPolicy: Local` khi ứng dụng cần biết nguồn gốc request.

```bash
# Tạo NodePort Service với policy mặc định (Cluster)
kubectl expose deployment web --port=80 --type=NodePort --name=web-nodeport

# Kiểm tra NodePort được assign
kubectl get svc web-nodeport
# NAME           TYPE       CLUSTER-IP    PORT(S)        AGE
# web-nodeport   NodePort   10.96.XX.XX   80:3XXXX/TCP   Xs
NODEPORT=$(kubectl get svc web-nodeport -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort: $NODEPORT"
```

**Verify — externalTrafficPolicy: Cluster (default):**

```bash
# Curl từ máy host đến NodePort (Vagrant dùng IP host-only, Multipass dùng VM IP)
NODE_IP=$(kubectl get nodes worker1 -o jsonpath='{.status.addresses[0].address}')
curl -s http://${NODE_IP}:${NODEPORT} | head -5
# → HTML response từ nginx

# Xem source IP trong access log của pods
kubectl logs -l app=web --tail=5
# → source IP là Node IP (10.0.X.X hoặc 192.168.X.X) — KHÔNG phải IP máy bạn
# Lý do: kube-proxy SNAT packet để đảm bảo reply về đúng Node nhận request
```

**Đổi sang externalTrafficPolicy: Local:**

```bash
kubectl patch svc web-nodeport -p '{"spec":{"externalTrafficPolicy":"Local"}}'

# Xác nhận policy đã đổi
kubectl get svc web-nodeport -o jsonpath='{.spec.externalTrafficPolicy}'
# → Local

# Curl lại từ máy host
curl -s http://${NODE_IP}:${NODEPORT} | head -5
kubectl logs -l app=web --tail=5
# → Source IP giờ là IP máy bạn (IP thật được giữ nguyên)

# Lưu ý: nếu Node được curl không có Pod web → connection refused
# Verify: kiểm tra pod nào đang chạy trên Node nào
kubectl get pods -l app=web -o wide
```

---

## 🔬 Bước 6: Thử nghiệm nftables mode (K8s v1.33+)

> **Mục đích:** nftables là người kế nhiệm của iptables trong Linux kernel — cú pháp rõ ràng hơn, atomic rule update (không race condition khi cập nhật nhiều rule cùng lúc), hiệu năng tốt hơn với ruleset lớn. GA trong K8s v1.33.

```bash
# Trên Control Plane

# Chỉnh kube-proxy ConfigMap sang nftables mode
kubectl edit configmap kube-proxy -n kube-system
# Sửa: mode: "ipvs"  →  mode: "nftables"

# Restart kube-proxy
kubectl rollout restart daemonset kube-proxy -n kube-system
kubectl rollout status daemonset kube-proxy -n kube-system

# Xác nhận mode
kubectl get configmap kube-proxy -n kube-system -o jsonpath='{.data.config\.conf}' | grep mode
# → mode: nftables
```

```bash
# SSH vào Worker Node để xem nftables rules

# Cài nftables tools nếu chưa có
sudo apt install -y nftables

# Xem tables và chains do kube-proxy tạo
sudo nft list tables
# → table ip kube-proxy

# Xem toàn bộ ruleset
sudo nft list table ip kube-proxy
# → Cấu trúc rõ ràng hơn iptables: chains, sets, rules trong cùng 1 table

# So sánh: iptables KUBE-SERVICES giờ trống (nftables quản lý thay)
sudo iptables -t nat -L KUBE-SERVICES -n
# → Ít rule hơn so với iptables mode
```

**Verify — Service vẫn hoạt động:**

```bash
kubectl run curl-test3 --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')
# → HTML response — nftables đang xử lý load balancing
```

> **Lưu ý:** nftables mode yêu cầu kernel ≥ 5.13 (Ubuntu 22.04+). Ubuntu 26.04 đủ điều kiện. Nếu cluster đang dùng cho production và cần rollback, đổi lại `mode: "iptables"` và restart.

---

## 📚 Kiến thức học được

### Service và ClusterIP

- **Pod có IP động** — Pod chết đi, IP mất. Service cung cấp ClusterIP ổn định đứng trước các Pod.
- **ClusterIP chỉ accessible từ bên trong cluster** — không route được từ máy host, phải dùng Pod trung gian để test.
- **kube-proxy** chạy trên mọi Node, watch API Server, lập trình rules vào kernel mỗi khi Service/EndpointSlice thay đổi.

### EndpointSlice vs Endpoints

- `Endpoints` cũ lưu toàn bộ Pod IP trong **1 object** → 1000 pods = 1 object khổng lồ, mỗi lần Pod thay đổi phải ghi lại toàn bộ.
- `EndpointSlice` chia nhỏ tối đa **100 pods/slice** → cập nhật chỉ ảnh hưởng 1 slice, giảm tải etcd và API Server.
- K8s v1.33: `Endpoints` API deprecated, kube-proxy đọc EndpointSlice làm nguồn chân lý.

### iptables mode: KUBE-SERVICES → KUBE-SVC → KUBE-SEP

```
Packet đến ClusterIP:80
    ▼ KUBE-SERVICES        match dst=ClusterIP → nhảy vào KUBE-SVC
    ▼ KUBE-SVC-xxx         load balance bằng --probability (statistic module)
    ▼ KUBE-SEP-yyy         DNAT → Pod IP:Port thực
```

- Probability tính theo **conditional probability**: 3 pods → 1/3, 1/2, 1 (mỗi pod nhận đúng 33%).
- **O(n)**: 1000 Services = kernel phải duyệt ~5000 rules mỗi packet.

### IPVS mode: Hash table O(1)

- Kube-proxy tạo **virtual server** (ClusterIP) và **real servers** (Pod IPs) trong kernel IPVS subsystem.
- **Tra cứu O(1)** dù cluster có 10,000 Services — không phụ thuộc số lượng rule.
- **Interface `kube-ipvs0`** (state DOWN là bình thường — dummy interface để bind ClusterIP).
- Hỗ trợ nhiều LB algorithm: `rr`, `lc`, `dh`, `sh`, `sed`, `nq` — iptables chỉ có random.

### nftables mode: Tương lai

- **Atomic rule update** — iptables cập nhật từng rule một, có thể race condition trong thời gian ngắn. nftables apply toàn bộ ruleset mới trong 1 transaction.
- Cú pháp rõ ràng hơn: tất cả rules trong `table ip kube-proxy` thay vì rải rác nhiều chain.
- GA từ K8s v1.33, yêu cầu kernel ≥ 5.13 (Ubuntu 22.04+).

### externalTrafficPolicy

| | Cluster (default) | Local |
|---|---|---|
| **Forward đến** | Pod bất kỳ trên bất kỳ Node | Chỉ Pod trên Node nhận traffic |
| **Source IP** | Mất — Node SNAT để đảm bảo reply | Giữ nguyên IP thật của client |
| **Load balance** | Đều giữa tất cả Pods | Có thể lệch nếu Pods không đều |
| **Use case** | Traffic thông thường | WAF, rate-limiting theo IP, audit log |

> **Quan sát thực tế:** Sau khi đổi sang `Local`, nginx access log thấy IP máy bạn thay vì Node IP.

---

## ✅ Câu hỏi kiểm tra

1. Trong iptables mode, rule `--probability` được tính toán như thế nào cho 3 pods? (Gợi ý: 1/3, 1/2, 1/1)
2. Tại sao IPVS dùng hash table trong khi iptables dùng danh sách tuần tự?
3. Khi dùng `externalTrafficPolicy: Local`, điều gì xảy ra nếu Node không có Pod nào?
4. EndpointSlice giải quyết vấn đề gì của Endpoints? Tại sao cập nhật 1 EndpointSlice nhanh hơn?
5. Ưu điểm của nftables so với iptables là gì? Tại sao K8s cần atomic rule update?

---

## 🧹 Dọn dẹp

```bash
kubectl delete deployment web
kubectl delete svc web-svc web-nodeport
```
