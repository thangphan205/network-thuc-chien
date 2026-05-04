# ThucChienCNI — Tự viết CNI Plugin từ đầu

## 🎯 Mục tiêu

Chứng minh rằng CNI plugin **không có gì huyền bí**: chỉ là một binary nhận env vars + JSON từ stdin, thực hiện thao tác Linux kernel, rồi trả JSON ra stdout. Flannel, Calico, Cilium đều follow đúng cùng contract này.

---

## 🗺️ Kiến trúc ThucChienCNI

```
Worker Node
┌──────────────────────────────────────────────────────────────────┐
│                                                                    │
│  cnitool (ADD)                                                     │
│      │ CNI_COMMAND=ADD                                             │
│      │ stdin: /etc/cni/net.d/10-thucchien.conflist                │
│      ▼                                                             │
│  /opt/cni/bin/thucchien-cni  (bash script)                       │
│      │                                                             │
│      ├─ 1. ipam_alloc() → /var/lib/thucchien-cni/ipam/<cid>      │
│      │      Tìm IP trống trong 10.88.0.0/24                       │
│      │      Ghi containerID → IP vào file                         │
│      │                                                             │
│      ├─ 2. ensure_bridge() → tạo bridge tc0 (10.88.0.1/24)       │
│      │                                                             │
│      ├─ 3. ip link add vtcXXXXXXXX type veth peer eth0 netns ...  │
│      │      vtcXXXXXXXX ← Host side, gắn vào bridge tc0          │
│      │      eth0        ← Pod side, trong netns                   │
│      │                                                             │
│      ├─ 4. nsenter --net=<netns> -- ip addr add 10.88.0.x/24     │
│      │      nsenter --net=<netns> -- ip route add default via ... │
│      │                                                             │
│      └─ 5. Trả CNI result JSON ra stdout                          │
│                                                                    │
│  Kết quả:                                                          │
│  ┌──────────────────────────┐   ┌─────────────────────────────┐   │
│  │ Network Namespace (Pod)  │   │ Host Network Namespace       │   │
│  │  eth0: 10.88.0.2/24     │   │  tc0: 10.88.0.1/24 (bridge) │   │
│  │   └── veth pair ─────────┼───┼──► vtcXXXXXXXX             │   │
│  └──────────────────────────┘   └─────────────────────────────┘   │
│                                                                    │
│  IPAM state: /var/lib/thucchien-cni/ipam/<containerID>            │
│              (content = "10.88.0.2")                              │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🔬 Bước 1: Cài đặt ThucChienCNI

```bash
# SSH vào worker node
vagrant ssh worker1   # hoặc multipass shell worker1

# Copy binary vào /opt/cni/bin/
sudo cp /path/to/thucchien-cni /opt/cni/bin/thucchien-cni
sudo chmod +x /opt/cni/bin/thucchien-cni

# Hoặc nếu bạn đã clone repo:
sudo cp ~/network-thuc-chien/kubernetes-networking/lab-module1/thucchien-cni/thucchien-cni \
    /opt/cni/bin/thucchien-cni
sudo chmod +x /opt/cni/bin/thucchien-cni

# Copy conflist
sudo mkdir -p /etc/cni/net.d
sudo cp ~/network-thuc-chien/kubernetes-networking/lab-module1/thucchien-cni/10-thucchien.conflist \
    /etc/cni/net.d/10-thucchien.conflist

# Verify
ls -la /opt/cni/bin/thucchien-cni
cat /etc/cni/net.d/10-thucchien.conflist
```

---

## 🔬 Bước 2: Kiểm tra VERSION và STATUS

```bash
# VERSION: plugin hỗ trợ spec version nào?
echo '{"cniVersion":"1.0.0","name":"thucchien-network","type":"thucchien-cni"}' \
  | sudo env CNI_COMMAND=VERSION CNI_PATH=/opt/cni/bin /opt/cni/bin/thucchien-cni

# Output:
# {
#   "cniVersion": "1.0.0",
#   "supportedVersions": ["0.3.0", "0.3.1", "0.4.0", "1.0.0"]
# }

# STATUS: plugin có sẵn sàng nhận lệnh không?
echo '{}' | sudo env CNI_COMMAND=STATUS CNI_PATH=/opt/cni/bin /opt/cni/bin/thucchien-cni
echo "Exit code: $?"
# Exit code: 0 → OK
```

---

## 🔬 Bước 3: Tạo Network Namespace thử nghiệm

```bash
# Tạo namespace
sudo ip netns add pod-demo
ip netns list
# pod-demo
```

---

## 🔬 Bước 4: Gọi ADD — ThucChienCNI cấp IP và tạo mạng

```bash
# Gọi cnitool ADD với ThucChienCNI
sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool add thucchien-network /var/run/netns/pod-demo

# Output CNI result JSON:
# {
#   "cniVersion": "1.0.0",
#   "interfaces": [
#     { "name": "vtcXXXXXXXX", "mac": "...", "sandbox": "" },
#     { "name": "eth0", "mac": "...", "sandbox": "/var/run/netns/pod-demo" }
#   ],
#   "ips": [
#     { "address": "10.88.0.2/24", "gateway": "10.88.0.1", "interface": 1 }
#   ],
#   ...
# }
```

---

## 🔬 Bước 5: Quan sát kết quả — Tất cả do bash script tạo ra

```bash
# 1. Bridge tc0 trên Host
ip link show tc0
ip addr show tc0
# tc0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
#   inet 10.88.0.1/24 scope global tc0

# 2. veth pair — host side gắn vào bridge
ip link show | grep vtc
# vtcXXXXXXXX: <BROADCAST,MULTICAST,UP,LOWER_UP> master tc0

# 3. Interface và IP bên trong pod-demo namespace
sudo ip netns exec pod-demo ip addr show
# eth0: inet 10.88.0.2/24

# Route trong namespace
sudo ip netns exec pod-demo ip route show
# default via 10.88.0.1 dev eth0

# 4. IPAM state file — đây là "database" của ThucChienCNI
ls /var/lib/thucchien-cni/ipam/
# <containerID>
cat /var/lib/thucchien-cni/ipam/<containerID>
# 10.88.0.2
```

---

## 🔬 Bước 6: Test kết nối thực tế

```bash
# Ping từ Host vào Pod (qua bridge tc0)
ping -c 3 10.88.0.2
# PING 10.88.0.2: 64 bytes from 10.88.0.2 icmp_seq=1 ttl=64

# Ping từ bên trong Pod ra ngoài (qua SNAT rule của ThucChienCNI)
sudo ip netns exec pod-demo ping -c 3 8.8.8.8
# PING 8.8.8.8: 64 bytes from 8.8.8.8 ...  (cần internet access trên Node)
```

---

## 🔬 Bước 7: Tạo Pod thứ 2 — ThucChienCNI cấp IP khác

```bash
# Tạo namespace thứ 2
sudo ip netns add pod-demo2

# ADD cho pod-demo2 — phải được cấp IP khác (10.88.0.3)
sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool add thucchien-network /var/run/netns/pod-demo2

# Kiểm tra IPAM cấp 2 IP khác nhau
ls /var/lib/thucchien-cni/ipam/
# <containerID-1>  ← pod-demo
# <containerID-2>  ← pod-demo2

cat /var/lib/thucchien-cni/ipam/*
# 10.88.0.2
# 10.88.0.3

# Ping giữa 2 Pod (qua bridge tc0 — không cần VXLAN!)
sudo ip netns exec pod-demo ping -c 3 10.88.0.3
# PING 10.88.0.3: 64 bytes from 10.88.0.3 ...
```

---

## 🔬 Bước 8: Gọi DEL — Thu hồi tài nguyên

```bash
# DEL pod-demo
sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool del thucchien-network /var/run/netns/pod-demo

# Verify: IP đã được giải phóng
ls /var/lib/thucchien-cni/ipam/
# Chỉ còn 1 file (pod-demo2)

# veth của pod-demo đã bị xóa
ip link show | grep vtc
# Chỉ còn veth của pod-demo2

# Xóa namespace
sudo ip netns del pod-demo
```

---

## 🔬 Bước 9: Simulate Node Crash — IPAM leak và GC

```bash
# Tạo namespace, ADD
sudo ip netns add pod-crash
sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=/etc/cni/net.d \
  cnitool add thucchien-network /var/run/netns/pod-crash

ls /var/lib/thucchien-cni/ipam/
# 3 files: pod-demo2, pod-crash, ...

# Simulate crash: xóa namespace MÀ KHÔNG GỌI DEL
sudo ip netns del pod-crash

# IPAM state vẫn còn! IP bị giữ
ls /var/lib/thucchien-cni/ipam/
# Vẫn có file của pod-crash → "zombie IP"

# Fix thủ công (trong K8s thực tế thì kubelet gọi GC)
# Tìm containerID của pod-crash và xóa state file
sudo rm /var/lib/thucchien-cni/ipam/<containerID-of-pod-crash>
```

---

## 🔬 Bước 10: Đọc source code và so sánh với Flannel

```bash
# Xem source code ThucChienCNI
cat /opt/cni/bin/thucchien-cni

# So sánh với Flannel conflist thực tế (nếu đã cài Flannel từ lab trước)
cat /etc/cni/net.d/10-flannel.conflist
```

**ThucChienCNI làm gì giống Flannel (bridge mode)?**

| Thao tác | ThucChienCNI | Flannel (bridge mode) |
| :--- | :--- | :--- |
| Tạo bridge | `tc0` (bash `ip link add`) | `cni0` (binary bridge plugin) |
| IPAM | File-based bash script | `host-local` plugin (Go binary) |
| veth naming | `vtcXXXXXXXX` | `vethXXXXXXXX` |
| SNAT | `iptables MASQUERADE` | `iptables MASQUERADE` |
| Pod-to-Pod | Qua bridge (same Node) | Qua bridge + VXLAN (cross-Node) |

**ThucChienCNI KHÔNG có (để giữ code đơn giản):**
- Cross-Node routing (không có VXLAN/BGP → chỉ hoạt động trong 1 Node)
- Chained plugins (portmap, bandwidth)
- IPv6 support

---

## ✅ Câu hỏi kiểm tra

1. Tại sao `log()` trong ThucChienCNI ghi ra `stderr` thay vì `stdout`?
2. IPAM state file chứa gì? Tại sao cần file này?
3. Điều gì xảy ra nếu bạn gọi `ADD` 2 lần cho cùng 1 containerID? Thử nghiệm để kiểm tra.
4. Vì sao `DEL` phải idempotent? Tình huống nào kubelet gọi DEL khi netns đã không còn tồn tại?
5. ThucChienCNI có thể kết nối Pod trên 2 Node khác nhau không? Cần thêm gì để làm được điều đó?

---

## 🧹 Dọn dẹp

```bash
# Xóa namespaces
sudo ip netns del pod-demo  2>/dev/null || true
sudo ip netns del pod-demo2 2>/dev/null || true

# Xóa bridge
sudo ip link del tc0 2>/dev/null || true

# Xóa IPAM state
sudo rm -rf /var/lib/thucchien-cni/

# Xóa iptables MASQUERADE rule
sudo iptables -t nat -D POSTROUTING -s 10.88.0.0/24 ! -o tc0 -j MASQUERADE 2>/dev/null || true

# Xóa binary và config
sudo rm -f /opt/cni/bin/thucchien-cni
sudo rm -f /etc/cni/net.d/10-thucchien.conflist
```
