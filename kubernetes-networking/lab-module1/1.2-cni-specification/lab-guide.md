# Lab 1.2: Tự viết CNI Specification và kích hoạt bằng cnitool

## 🎯 Mục tiêu
- Hiểu cấu trúc file `.conflist` của CNI.
- Tự tay kích hoạt các **CNI operations** (ADD, DEL, GC, STATUS, VERSION) bằng `cnitool`.
- Quan sát bridge, veth, IP được tạo ra như thế nào.
- Simulate resource leak và dùng operation GC để dọn dẹp.

## ✅ Yêu cầu tiên quyết
- Có quyền root trên Worker Node (Ubuntu 24.04 hoặc 26.04).
- Cần cài CNI plugin binary và `cnitool`.

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
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" \
  | sudo tar -C /opt/cni/bin -xz

ls /opt/cni/bin/
# bridge, portmap, host-local, loopback, firewall...
```

> **ARM64 (Apple Silicon):** Thay `amd64` thành `arm64` trong URL trên.

---

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
export CNI_PATH=/opt/cni/bin
export NETCONFPATH=/etc/cni/net.d

sudo -E cnitool add mylab-network /var/run/netns/mytest-ns
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
# 10.99.0.2  ← file tên = IP đã cấp, nội dung = container ID
cat /var/lib/cni/networks/mylab-network/10.99.0.2
```

---

## 🔬 Bước 8: Gọi DEL để giải phóng

```bash
sudo -E cnitool del mylab-network /var/run/netns/mytest-ns

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
sudo -E cnitool add mylab-network /var/run/netns/leaked-ns

# Xác nhận IP đã được cấp
ls /var/lib/cni/networks/mylab-network/
# 10.99.0.2

# Simulate crash: xóa namespace TRỰC TIẾP mà không gọi DEL
# (DEL không được chạy — giống khi Node crash đột ngột)
sudo ip netns del leaked-ns

# Kiểm tra: IP vẫn bị "giữ" trong IPAM state
ls /var/lib/cni/networks/mylab-network/
# 10.99.0.2  ← vẫn còn! Đây là resource leak.

# Dùng GC để dọn dẹp — truyền danh sách container ID còn sống (rỗng = không có gì)
sudo -E CNI_PATH=/opt/cni/bin cnitool gc mylab-network

# Kiểm tra sau GC
ls /var/lib/cni/networks/mylab-network/
# (trống) ← GC đã dọn sạch IP bị leak
```

---

## 🔬 Bước 10: Thử nghiệm VERSION và STATUS operations

**VERSION** — query xem plugin hỗ trợ CNI spec version nào:

```bash
export CNI_PATH=/opt/cni/bin
export NETCONFPATH=/etc/cni/net.d

sudo -E cnitool version mylab-network
# Output JSON: {"cniVersion":"1.1.0","supportedVersions":["0.1.0","0.2.0","0.3.0","0.3.1","0.4.0","1.0.0","1.1.0"]}
# → Plugin bridge hỗ trợ nhiều spec versions, backwards compatible
```

**STATUS** — kiểm tra plugin có sẵn sàng nhận lệnh không:

```bash
sudo -E cnitool status mylab-network
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
