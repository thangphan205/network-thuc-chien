# Lab 1.2: Tự viết CNI Specification và kích hoạt bằng cnitool

## 🎯 Mục tiêu
- Hiểu cấu trúc file `.conflist` của CNI.
- Tự tay kích hoạt các **CNI operations** (ADD, DEL, GC, STATUS, VERSION) bằng `cnitool`.
- Quan sát bridge, veth, IP được tạo ra như thế nào.
- Simulate resource leak và dùng operation GC để dọn dẹp.

## ✅ Yêu cầu tiên quyết
- Có quyền root trên **1 Linux VM** (Ubuntu 24.04 hoặc 26.04).
- **Không cần K8s cluster đầy đủ** — lab này chạy trực tiếp trên OS của VM, không dùng `kubectl`.
- Cần cài CNI plugin binary và `cnitool` (hướng dẫn ở Bước 2–3).

---

## 🔬 Bước 0: Chuẩn bị VM

### Trường hợp A — VM còn từ Lab trước (chưa xóa)

```bash
# Kiểm tra VM đang chạy không
multipass list          # Multipass
vagrant status          # Vagrant
```

Nếu VM đang `stopped`:
```bash
multipass start worker1           # Multipass
vagrant up worker1                # Vagrant
```

→ **Bỏ qua phần B, đi thẳng Bước 1.**

---

### Trường hợp B — VM đã bị xóa (tạo lại từ đầu)

Lab này chỉ cần **1 VM** — không cần init cluster hay join worker.

```bash
# Multipass (macOS / Windows / Linux) — chạy từ thư mục lab-module0/
multipass launch 26.04 --name worker1 --cpus 2 --memory 2G --disk 10G --cloud-init k8s-cloud-init.yaml

# Vagrant — chạy từ thư mục lab-module0/
vagrant up worker1
```

Chờ VM khởi động xong:
```bash
multipass list          # Multipass — worker1 phải ở trạng thái Running
vagrant status          # Vagrant — worker1 phải ở trạng thái running
```

> **Lưu ý:** `k8s-cloud-init.yaml` cài sẵn containerd, kubelet, kubeadm — nhưng lab này không dùng K8s, chỉ cần Linux thuần để thực hành CNI.

---

## 🔬 Bước 1: SSH vào Worker Node

```bash
# Vagrant
vagrant ssh worker1

# Multipass
multipass shell worker1
```

---

## 🔬 Bước 2: Cài CNI Plugin Binaries

```bash
CNI_VERSION="v1.9.1"
sudo mkdir -p /opt/cni/bin
# Tự động detect architecture
ARCH=$(dpkg --print-architecture)   # amd64 hoặc arm64
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz" \
  | sudo tar -C /opt/cni/bin -xz

# Verify đúng arch (tránh exec format error)
file /opt/cni/bin/bridge
# → ELF 64-bit LSB executable, x86-64     (Intel/AMD)
# → ELF 64-bit LSB executable, ARM aarch64 (Apple Silicon / ARM server)

ls /opt/cni/bin/
# bridge, portmap, host-local, loopback, firewall...
```

## 🔬 Bước 3: Cài cnitool

```bash
# Cài Go (Ubuntu 24.04/26.04 đều có sẵn trong apt)
sudo apt-get install -y golang-go

# Kiểm tra phiên bản (cần Go 1.20+)
go version

# Build cnitool
go install github.com/containernetworking/cni/cnitool@latest

# Copy vào PATH hệ thống
sudo cp ~/go/bin/cnitool /usr/local/bin/
cnitool --help
```

> **Lưu ý:** Nếu `go install` báo lỗi module version, dùng snap thay thế:
> ```bash
> sudo snap install go --classic
> export PATH=$PATH:/snap/bin
> go install github.com/containernetworking/cni/cnitool@latest
> ```

---

## 🔬 Bước 4: Viết file .conflist

```bash
sudo mkdir -p /etc/cni/net.d

sudo tee /etc/cni/net.d/10-mylab.conflist <<'EOF'
{
  "cniVersion": "1.1.0",
  "name": "mylab-network",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "mylab0",
      "isGateway": true,
      "ipMasq": true,
      "ipam": {
        "type": "host-local",
        "ranges": [[{"subnet": "10.99.0.0/24"}]],
        "routes": [{"dst": "0.0.0.0/0"}]
      }
    },
    { "type": "portmap", "capabilities": {"portMappings": true} }
  ]
}
EOF
```

---

## 🔬 Bước 5: Tạo Network Namespace thử nghiệm

```bash
sudo ip netns add mytest-ns
ip netns list
# mytest-ns
```

---

## 🔬 Bước 6: Gọi CNI ADD thủ công

```bash
# Dùng 'sudo env' để truyền biến môi trường (sudo -E bị ignore trên Ubuntu 26.04)
sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool add mylab-network /var/run/netns/mytest-ns
# Output JSON: IP được cấp, interface info
```

---

## 🔬 Bước 7: Kiểm tra kết quả

```bash
# IP trong namespace
sudo ip netns exec mytest-ns ip addr show
# → eth0 có IP từ subnet 10.99.0.0/24

# Bridge trên Host
ip link show mylab0
ip addr show mylab0
# → mylab0 có IP 10.99.0.1 (gateway)

# IPAM state file — ghi nhận IP đã cấp
ls /var/lib/cni/networks/mylab-network/
# 10.99.0.2   ← tên file = IP đã cấp
# last_reserved_ip.0  ← IPAM dùng để track IP tiếp theo

# Xem container ID được lưu trong state file
# (host-local IPAM dùng container ID để biết ai đang giữ IP này)
cat /var/lib/cni/networks/mylab-network/10.99.0.2
# → in ra container ID dạng hex, ví dụ: 7a3f1c2d4e5b...
# cnitool tự sinh container ID ngẫu nhiên mỗi lần add

# Container ID này tương đương với CNI_CONTAINERID mà kubelet truyền vào thực tế
# Trong K8s: container ID = ID của pause container (lấy từ containerd/CRI)
printf "Container ID: "; cat /var/lib/cni/networks/mylab-network/10.99.0.2; echo
```

---

## 🔬 Bước 8: Gọi DEL để giải phóng

```bash
sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool del mylab-network /var/run/netns/mytest-ns

ls /var/lib/cni/networks/mylab-network/
# File 10.99.0.2 đã biến mất → IP đã được trả về pool

sudo ip netns del mytest-ns
```

---

## 🔬 Bước 9: Simulate Resource Leak và dùng GC

Đây là tình huống thực tế: Node crash khiến DEL không chạy được.

```bash
# Tạo lại namespace, ADD để cấp IP
sudo ip netns add leaked-ns
sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool add mylab-network /var/run/netns/leaked-ns

# Xác nhận IP đã được cấp
ls /var/lib/cni/networks/mylab-network/
# 10.99.0.2

# Simulate crash: xóa namespace TRỰC TIẾP mà không gọi DEL
# (DEL không được chạy — giống khi Node crash đột ngột)
sudo ip netns del leaked-ns

# Kiểm tra: IP vẫn bị "giữ" trong IPAM state
ls /var/lib/cni/networks/mylab-network/
# 10.99.0.2  ← vẫn còn! Đây là resource leak.

# Gọi GC — cnitool gc yêu cầu <net> <netns>
# Nếu chạy thiếu netns sẽ báo usage error:
#   cnitool gc <net> <netns>
# ubuntu@worker1:~$ sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
#   cnitool gc mylab-network
# cnitool: Add, check, remove, gc or status network interfaces from a network namespace

# Vì leaked-ns đã bị xóa, tạo anchor-ns tạm làm "valid attachment" anchor
# GC sẽ xóa tất cả state KHÔNG thuộc netns này
sudo ip netns add anchor-ns

sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool gc mylab-network /var/run/netns/anchor-ns
# → anchor-ns không có attachment nào → GC dọn sạch toàn bộ stale state

sudo ip netns del anchor-ns
```

> **So sánh với K8s thực tế:** `cnitool` bắt buộc truyền `<netns>` argument — đó là giới hạn của debug tool, không phải cách K8s hoạt động. Kubelet gọi GC bằng cách truyền danh sách **gcAttachments** qua stdin (không tạo namespace tạm):
> ```json
> {"gcAttachments": [{"containerID": "abc123", "ifname": "eth0"}, {"containerID": "def456", "ifname": "eth0"}]}
> ```
> Plugin nhận list này, so sánh với state file, xóa những attachment không có trong list. `anchor-ns` ở trên là workaround chỉ dùng khi debug với `cnitool`.

```bash
# Kiểm tra sau GC
ls /var/lib/cni/networks/mylab-network/
# (trống) ← leaked IP đã bị xóa bởi GC
```

---

## 🔬 Bước 10: Thử nghiệm VERSION và STATUS operations

**VERSION** — query xem plugin hỗ trợ CNI spec version nào:

> **Lưu ý:** `cnitool` không có subcommand `version` (chỉ hỗ trợ: add, check, remove, gc, status). Gọi plugin binary trực tiếp với `CNI_COMMAND=VERSION`:

```bash
# Gọi bridge plugin trực tiếp — truyền config tối thiểu qua stdin
echo '{"cniVersion":"1.1.0","name":"mylab-network","type":"bridge"}' \
  | sudo env CNI_COMMAND=VERSION CNI_PATH=/opt/cni/bin /opt/cni/bin/bridge
# Output JSON: {"cniVersion":"1.1.0","supportedVersions":["0.1.0","0.2.0","0.3.0","0.3.1","0.4.0","1.0.0","1.1.0"]}
# → Plugin bridge hỗ trợ nhiều spec versions, backwards compatible
```

**STATUS** — kiểm tra plugin có sẵn sàng nhận lệnh không:

> **Lưu ý:** `cnitool status` cũng yêu cầu `<netns>` argument (giới hạn của cnitool). Gọi plugin trực tiếp:

```bash
echo '{"cniVersion":"1.1.0","name":"mylab-network","type":"bridge"}' \
  | sudo env CNI_COMMAND=STATUS CNI_PATH=/opt/cni/bin /opt/cni/bin/bridge
# Exit code 0 = plugin OK
# Exit code 1 = plugin lỗi (daemon crash, config sai)
echo "Exit code: $?"
```

> **So sánh với ADD/DEL:** VERSION và STATUS là **meta operations** — không tạo/xóa network resource. kubelet dùng STATUS để kiểm tra trước khi schedule Pod lên Node.

---

## ✅ Câu hỏi kiểm tra

1. Sau lệnh ADD, file nào được tạo trong `/var/lib/cni/networks/`? Nó lưu gì bên trong?
2. Bridge `mylab0` có IP không? IP đó lấy từ đâu trong `.conflist`?
3. Nếu gọi ADD hai lần cho cùng namespace, điều gì xảy ra?
4. Trong Bước 9, tại sao xóa namespace trực tiếp (`ip netns del`) mà không gọi DEL lại gây ra resource leak? GC giải quyết bằng cơ chế gì?
5. Biến `CNI_NETNS` mà kubelet truyền cho CNI plugin trỏ vào path nào trên filesystem? (Gợi ý: `/proc/<PID>/fd/` hoặc `/var/run/netns/`)
6. Output của VERSION cho biết plugin hỗ trợ những spec version nào? Tại sao plugin cần backwards compatible với các version cũ?

---

## 🧹 Dọn dẹp

```bash
# Xóa bridge và state files còn lại
sudo ip link delete mylab0
sudo rm -rf /var/lib/cni/networks/mylab-network/
sudo rm /etc/cni/net.d/10-mylab.conflist
```
