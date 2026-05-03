# Lab 1.1: Inspect Network Namespace của Pod từ Worker Node

## 🎯 Mục tiêu
- Xác nhận `pause` container đang tồn tại trên Node.
- Dùng `ip netns` để xem và thao tác trong Network Namespace.
- Tìm `veth pair` kết nối Pod vào Node bằng kỹ thuật `@if` index.
- Chui vào Network Namespace của Pod từ OS của Node.

## ✅ Yêu cầu tiên quyết
- Cluster 3 nodes đang chạy (CNI đã cài).
- SSH được vào Worker Node.
- Đã cài `netshoot` hoặc có `nsenter` trên Node.

---

## 🔬 Bước 0: Chuẩn bị Cluster

### Trường hợp A — Cluster còn từ Module 0 (chưa xóa)

Kiểm tra nhanh:
```bash
# Vagrant
vagrant status

# Multipass
multipass list
```

Nếu VMs đang `stopped` thì bật lại:
```bash
# Vagrant
vagrant up

# Multipass
multipass start controlplane worker1 worker2
```

Sau đó SSH vào controlplane và kiểm tra cluster còn sống không:
```bash
# Vagrant
vagrant ssh controlplane

# Multipass
multipass shell controlplane
```

```bash
kubectl get nodes
```

Nếu tất cả nodes `Ready` → **bỏ qua Bước 0 và đi thẳng Bước 1**.

---

### Trường hợp B — Cluster đã bị xóa (làm lại từ đầu)

**B1 — Tạo lại 3 VMs:**

```bash
# Vagrant (Windows/Linux/macOS Intel) — chạy từ thư mục lab-module0/
vagrant up

# Multipass (macOS Apple Silicon) — chạy từ thư mục lab-module0/
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
# SSH vào controlplane
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

## 🔬 Bước 1: Tạo Pod thử nghiệm

```bash
kubectl run nginx-test --image=nginx --restart=Never
kubectl get pod nginx-test -o wide
# Ghi lại NODE và POD IP
```

---

## 🔬 Bước 2: SSH vào Worker Node chứa Pod

```bash
# Vagrant
vagrant ssh worker1

# Multipass
multipass shell worker1
```

---

## 🔬 Bước 3: Tìm Pause Container bằng crictl

```bash
# Liệt kê tất cả container đang chạy trên Node
sudo crictl ps

# Bạn sẽ thấy 2 container liên quan đến nginx-test:
#   1. container nginx-test (app container)
#   2. container pause (infra container — giữ Network Namespace)
# Ghi lại Container ID của pause container

# Lấy PID từ PAUSE container (không phải nginx)
# Vì pause là người giữ Network Namespace, đây là PID cần dùng
PAUSE_ID=<CONTAINER_ID_CUA_PAUSE>
POD_PID=$(sudo crictl inspect $PAUSE_ID | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['pid'])")
echo "Pause container PID: $POD_PID"
```

---

## 🔬 Bước 4: Xem Network Namespace bằng ip netns

```bash
# Liệt kê tất cả Network Namespaces trên Node
# (CNI tạo ra 1 namespace cho mỗi Pod)
sudo ip netns list
# cni-abc12345-1234-5678-abcd-123456789012 (id: 5)

# Chạy lệnh IP bên trong namespace của Pod
# (không cần ssh vào Pod)
sudo ip netns exec cni-abc12345-... ip addr show
# 2: eth0@if7: <BROADCAST,UP> mtu 1450 ...
#    inet 10.244.x.x/32 scope global eth0
#    ↑ Số "7" sau "@if" = index của veth đầu bên Node

# Xác nhận IP khớp với kubectl get pod -o wide
```

---

## 🔬 Bước 5: Tìm veth pair bằng kỹ thuật @if index

```bash
# Từ bước trên, eth0@if7 → index 7 là veth ngoài Node
# Tìm interface có index đó:
sudo ip link show | grep "^7:"
# 7: vethXXXXXX@if2: <BROADCAST,MULTICAST,UP> master cni0 ...
#    ↑ Đây là đầu Node của veth pair kết nối vào Pod

# Xem tất cả veth đang gắn vào bridge cni0
ip link show | grep "master cni0"
ip addr show | grep -A2 veth
```

---

## 🔬 Bước 6: Chui vào Network Namespace của Pod bằng nsenter

```bash
# Dùng POD_PID đã lấy từ Bước 3 (PID của pause container)
sudo nsenter -t $POD_PID -n ip addr show
# → Thấy eth0 với IP của Pod — đứng từ HOST OS!
# → IP này phải khớp với kubectl get pod -o wide (Nguyên tắc #3)

sudo nsenter -t $POD_PID -n ip route show
# → Thấy default route của Pod

sudo nsenter -t $POD_PID -n ss -tlnp
# → Thấy các port đang listen bên trong Pod
```

---

## 🔬 Bước 7: Bắt gói tin từ phía Node trên veth pair

```bash
# Lấy tên veth pair của Pod (từ Bước 5)
VETH=$(ip link show | grep "master cni0" | grep veth | head -1 | awk '{print $2}' | tr -d ':')

# Bắt gói tin trực tiếp trên veth pair của Pod
sudo tcpdump -i $VETH -nn
```

Từ terminal khác, gửi traffic vào Pod:
```bash
kubectl exec -it nginx-test -- curl localhost
```

---

## ✅ Câu hỏi kiểm tra

1. Container `pause` giữ vai trò gì? Nó có đang chạy process nào không?
2. IP của Pod trong `nsenter` có khớp với `kubectl get pod -o wide` không? Nguyên tắc K8s nào đảm bảo điều này?
3. Tên veth trên Node được đặt tên theo quy tắc gì? Số `@if` index cho biết điều gì?
4. Dùng `kubectl exec` ping từ `nginx-test` sang một Pod khác. Source IP trong tcpdump trên Node nhận là IP gì — IP của Pod hay IP của Node?

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod nginx-test
```
