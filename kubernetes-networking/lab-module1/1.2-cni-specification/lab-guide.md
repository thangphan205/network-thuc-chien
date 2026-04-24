# Lab 1.2: Tự viết CNI Specification và kích hoạt bằng cnitool

## 🎯 Mục tiêu
- Hiểu cấu trúc file `.conflist` của CNI.
- Tự tay tạo Network Namespace và gọi `cnitool ADD` để cấp IP.
- Quan sát bridge, veth, IP được tạo ra như thế nào.

## ✅ Yêu cầu tiên quyết
- Có quyền root trên Linux machine (Worker Node hoặc Ubuntu VM).
- Cần cài CNI plugin binary.

---

## 🔬 Bước 1: Cài CNI Plugin Binaries

```bash
vagrant ssh worker1  # hoặc: multipass shell worker1

CNI_VERSION="v1.4.0"
sudo mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" \
  | sudo tar -C /opt/cni/bin -xz

ls /opt/cni/bin/
# bridge, portmap, host-local, loopback, firewall...
```

---

## 🔬 Bước 2: Cài cnitool

```bash
sudo apt install -y golang-go
go install github.com/containernetworking/cni/cnitool@latest
sudo cp ~/go/bin/cnitool /usr/local/bin/
```

---

## 🔬 Bước 3: Viết file .conflist

```bash
sudo mkdir -p /etc/cni/net.d

sudo tee /etc/cni/net.d/10-mylab.conflist <<'EOF'
{
  "cniVersion": "1.0.0",
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

## 🔬 Bước 4: Tạo Network Namespace thử nghiệm

```bash
sudo ip netns add mytest-ns
ip netns list
# mytest-ns
```

---

## 🔬 Bước 5: Gọi CNI ADD thủ công

```bash
export CNI_PATH=/opt/cni/bin
export NETCONFPATH=/etc/cni/net.d

sudo -E cnitool add mylab-network /var/run/netns/mytest-ns
# Output JSON: IP được cấp, interface info
```

---

## 🔬 Bước 6: Kiểm tra kết quả

```bash
# IP trong namespace
sudo ip netns exec mytest-ns ip addr show

# Bridge trên Host
ip link show mylab0
ip addr show mylab0

# IPAM state file
ls /var/lib/cni/networks/mylab-network/
# 10.99.0.2  ← File ghi nhận IP đã cấp
```

---

## 🔬 Bước 7: Gọi DEL để giải phóng

```bash
sudo -E cnitool del mylab-network /var/run/netns/mytest-ns

ls /var/lib/cni/networks/mylab-network/
# File 10.99.0.2 đã biến mất

sudo ip netns del mytest-ns
```

---

## ✅ Câu hỏi kiểm tra

1. Sau lệnh ADD, file nào được tạo trong `/var/lib/cni/networks/`? Nó lưu gì?
2. Bridge `mylab0` có IP không? IP đó lấy từ đâu?
3. Nếu gọi ADD hai lần cho cùng namespace, điều gì xảy ra?
