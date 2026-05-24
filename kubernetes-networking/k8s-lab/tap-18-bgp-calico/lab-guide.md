# Lab Tập 18: BGP trong Calico — Chuyển từ VXLAN sang BGP mode

Tập này chuyển Calico sang BGP mode (không encapsulation) và verify routing table thay đổi.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 11-12.
- `calicoctl` đã cài (từ Tập 12).
- `pod-a` trên `worker1` và `pod-b` trên `worker2` (tạo lại nếu cần).

---

## 🔬 Thí nghiệm 1: Xem IP Pool hiện tại và chuyển sang BGP mode

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Xem IP Pool hiện tại (VXLAN mode):
   ```bash
   calicoctl get ippool -o yaml | grep -E "encapsulation|cidr|name"
   # encapsulation: VXLANCrossSubnet
   ```

2. Chuyển sang BGP mode (không encapsulation):
   ```bash
   calicoctl patch ippool default-ipv4-ippool \
     --patch '{"spec": {"encapsulation": "None", "natOutgoing": true}}'
   ```

3. Verify:
   ```bash
   calicoctl get ippool default-ipv4-ippool -o yaml | grep encapsulation
   # encapsulation: None
   ```

4. Chờ Calico reload routes (~30 giây):
   ```bash
   kubectl -n calico-system rollout status daemonset/calico-node
   ```

---

## 🔬 Thí nghiệm 2: Quan sát thay đổi routing table

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Xem routing table mới — không còn tunnel:
   ```bash
   ip route show | grep 10.244
   # 10.244.0.0/26 via 192.168.64.10 dev eth0  ← Direct route tới controlplane
   # 10.244.1.0/26 dev cni0                    ← Local subnet
   # 10.244.2.0/26 via 192.168.64.12 dev eth0  ← Direct route tới worker2
   ```
   *Nhận xét:* Routes dùng `eth0` trực tiếp, không phải `vxlan.calico` hay bất kỳ tunnel interface nào.

2. Verify không còn VXLAN interface (hoặc đã down):
   ```bash
   ip link show | grep -i vxlan
   # (không có hoặc không active)
   ```

3. Xem bảng BGP routes được cài:
   ```bash
   ip route show | grep "bird\|bgp\|proto"
   # Có thể thấy các routes với proto BIRD
   ```

---

## 🔬 Thí nghiệm 3: Xem BGP sessions và verify không còn VXLAN

**Mở 2 terminal:**

**Terminal 1 — `worker1`, bắt traffic:**
```bash
multipass shell worker1

# Nghe VXLAN (8472) và ICMP
sudo tcpdump -i eth0 -n '(udp port 8472) or icmp' &
TCPDUMP_PID=$!
```

**Terminal 2 — `controlplane`, tạo traffic:**
```bash
multipass shell controlplane

# Tạo pods nếu chưa có
kubectl get pod pod-a pod-b 2>/dev/null || kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-a
spec:
  nodeName: worker1
  containers:
  - name: net
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-b
spec:
  nodeName: worker2
  containers:
  - name: net
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF
kubectl wait --for=condition=Ready pod/pod-a pod/pod-b --timeout=90s

POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
kubectl exec pod-a -- ping -c 5 $POD_B_IP
```

**Quay lại Terminal 1:**
- **Không thấy** dòng `> 8472` (không có VXLAN)
- Thấy ICMP trực tiếp: `10.244.1.X > 10.244.2.Y: ICMP echo request`

```bash
kill $TCPDUMP_PID
```

---

## 🔬 Thí nghiệm 4: Xem BGPConfiguration và node status

**Trên `controlplane`:**

1. Xem BGP configuration:
   ```bash
   calicoctl get bgpconfiguration default -o yaml
   # spec:
   #   asNumber: 64512           ← AS number của cluster
   #   nodeToNodeMeshEnabled: true  ← Full mesh enabled
   ```

2. Xem BGP session status từ controlplane:
   ```bash
   calicoctl node status
   # Calico process is running.
   # IPv4 BGP status
   # PEER ADDRESS  | PEER TYPE      | STATE | SINCE | INFO
   # 192.168.64.11 | node specific  | up    | ...   | Established
   # 192.168.64.12 | node specific  | up    | ...   | Established
   ```

3. Xem BGP peer từ worker1:
   ```bash
   # calicoctl node status bắt buộc chạy local trên node để đọc Unix Socket BIRD
   multipass exec worker1 -- sudo calicoctl node status
   ```

---

## 🧹 Dọn dẹp / Chuẩn bị cho tập tiếp theo

```bash
# Giữ nguyên BGP mode cho Tập 19 (Route Reflector)
# Không cần xóa gì
```

---

## ✅ Tổng kết

1. **BGP mode = không encapsulation:** IP Pool `encapsulation: None` → routes trực tiếp qua `eth0`, không qua tunnel.
2. **Routing table thay đổi:** Thay vì route qua VXLAN interface, giờ route thẳng qua `eth0` via Node IP.
3. **tcpdump confirm:** Không có UDP 8472, packet ICMP có source/dest là Pod IP thật (không wrapped).
4. **BIRD quản lý routes:** BGP sessions giữa các Nodes trao đổi Pod subnet routes — giống như datacenter routing.
