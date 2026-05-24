# Lab Tập 31: Cùng Node vs Khác Node — Đo latency và trace packet paths

Tập này deploy 4 pods để có 2 scenarios (same-node và cross-node), đo latency + bandwidth thực tế, và verify sockops counter tăng khi có same-node traffic.

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy với sockops enabled (từ Tập 27).
- Cluster có worker1 và worker2 đang sẵn sàng.
- `iperf3` có sẵn trong image `nicolaka/netshoot`.

---

## 🔬 Thí nghiệm 1: Deploy 4 pods cho 2 scenarios

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Deploy pods cho **same-node test** (cả hai trên worker1):
   ```bash
   kubectl run same-server \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker1"}}' \
     -- iperf3 -s -B 0.0.0.0

   kubectl run same-client \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker1"}}' \
     -- sleep infinity
   ```

2. Deploy pods cho **cross-node test** (server trên worker2, client trên worker1):
   ```bash
   kubectl run cross-server \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker2"}}' \
     -- iperf3 -s -B 0.0.0.0

   kubectl run cross-client \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker1"}}' \
     -- sleep infinity
   ```

3. Chờ tất cả Ready và lấy IPs:
   ```bash
   kubectl wait --for=condition=Ready \
     pod/same-server pod/same-client \
     pod/cross-server pod/cross-client \
     --timeout=120s

   SAME_IP=$(kubectl get pod same-server -o jsonpath='{.status.podIP}')
   CROSS_IP=$(kubectl get pod cross-server -o jsonpath='{.status.podIP}')
   echo "Same-node server IP : $SAME_IP  (worker1)"
   echo "Cross-node server IP: $CROSS_IP (worker2)"
   ```

4. Verify topology đúng:
   ```bash
   kubectl get pod -o wide | grep -E "same|cross"
   # same-client   ... worker1
   # same-server   ... worker1   ← cùng node với same-client
   # cross-client  ... worker1
   # cross-server  ... worker2   ← khác node với cross-client
   ```

---

## 🔬 Thí nghiệm 2: Đo latency — same-node vs cross-node

**Trên `controlplane`:**

1. **Latency — same-node (sockops bypass):**
   ```bash
   kubectl exec same-client -- ping -c 50 $SAME_IP | tail -3
   # 50 packets transmitted, 50 received, 0% packet loss
   # rtt min/avg/max/mdev = 0.048/0.062/0.089/0.008 ms
   # ← ~0.05-0.1ms: gần như loopback speed
   ```

2. **Latency — cross-node (TC + VXLAN):**
   ```bash
   kubectl exec cross-client -- ping -c 50 $CROSS_IP | tail -3
   # 50 packets transmitted, 50 received, 0% packet loss
   # rtt min/avg/max/mdev = 0.280/0.350/0.450/0.032 ms
   # ← ~0.3-0.5ms: network-bound
   ```

3. Tính ratio:
   ```bash
   echo "Latency ratio: 0.35ms / 0.06ms = ~6x slower cross-node"
   ```

   *Nhận xét:* ICMP ping đi qua sockops redirect khi same-node → thời gian xử lý gần bằng loopback trong kernel.

---

## 💥 Thí nghiệm 3: Đo bandwidth — same-node vs cross-node

**Trên `controlplane`:**

1. **Bandwidth — same-node (sockops):**
   ```bash
   kubectl exec same-client -- iperf3 -c $SAME_IP -t 10 -P 4
   # [SUM] 0.00-10.00 sec  23.0 GBytes  18.4 Gbits/sec  sender
   # ← Near-loopback speed: bypass TCP stack duplication
   ```

2. **Bandwidth — cross-node (TC + physical NIC):**
   ```bash
   kubectl exec cross-client -- iperf3 -c $CROSS_IP -t 10 -P 4
   # [SUM] 0.00-10.00 sec  2.63 GBytes  2.10 Gbits/sec  sender
   # ← Physical NIC speed + VXLAN overhead
   ```

3. Tính ratio:
   ```bash
   echo "Bandwidth ratio: 18.4 Gbps / 2.1 Gbps = ~8.7x higher same-node"
   ```

4. Verify cả 2 paths hoạt động bình thường (không drop):
   ```bash
   kubectl exec same-client -- iperf3 -c $SAME_IP -t 5 2>&1 | grep -E "sender|receiver"
   kubectl exec cross-client -- iperf3 -c $CROSS_IP -t 5 2>&1 | grep -E "sender|receiver"
   ```

---

## 🔬 Thí nghiệm 4: Verify sockops counter tăng

**Trên `controlplane`:**

1. Lấy cilium-agent pod trên worker1 (nơi same-client chạy):
   ```bash
   WORKER1_CILIUM=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium \
     --field-selector spec.nodeName=worker1 \
     -o name | head -1)
   echo "Cilium pod trên worker1: $WORKER1_CILIUM"
   ```

2. Ghi lại metrics trước khi test:
   ```bash
   kubectl -n kube-system exec -it $WORKER1_CILIUM -- \
     cilium bpf metrics list | grep -i "sock\|redirect\|forward"
   # Ghi lại số Packets hiện tại
   ```

3. Generate same-node traffic:
   ```bash
   kubectl exec same-client -- iperf3 -c $SAME_IP -t 5 &
   IPERF_PID=$!
   ```

4. Xem counter tăng trong khi traffic chạy:
   ```bash
   sleep 2
   kubectl -n kube-system exec -it $WORKER1_CILIUM -- \
     cilium bpf metrics list | grep -i "sock\|redirect\|forward"
   # Forwarded via sockops: XXXX packets  ← Tăng!
   wait $IPERF_PID
   ```

5. Verify cilium_lxc map — chỉ chứa Pods trên worker1:
   ```bash
   kubectl -n kube-system exec -it $WORKER1_CILIUM -- \
     cilium bpf endpoint list
   # ENDPOINT  FLAGS  IPv4        MAC
   # 1234      0x0    10.244.1.5  xx:xx  ← same-server (worker1)
   # 2345      0x0    10.244.1.8  yy:yy  ← same-client (worker1)
   # ← cross-server (10.244.2.x) KHÔNG có ở đây → sockops không redirect
   ```

   *Nhận xét:* `cilium_lxc` chỉ có Pods của node hiện tại → lookup miss với cross-server IP → sockops bỏ qua → TC path xử lý.

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod same-server same-client cross-server cross-client
```

---

## ✅ Tổng kết

1. **Same-node path (sockops):** BPF intercept `connect()` → lookup `cilium_lxc` map → found → `bpf_msg_redirect_hash()` → socket-to-socket redirect → ~0.05ms, ~18 Gbps. Bỏ qua hoàn toàn: veth, TC BPF, iptables, TCP stack duplication.
2. **Cross-node path (TC):** Không có trong `cilium_lxc` → sockops bỏ qua → packet xuống TCP stack → veth → TC BPF (policy check) → VXLAN encap → physical NIC → ~0.35ms, ~2 Gbps (network-bound).
3. **Tại sao sockops không thể cross-node:** sockops hoạt động ở socket buffer layer trong kernel — không có cơ chế gửi data qua physical NIC. Cross-node cần encapsulation và routing xảy ra dưới socket layer, ngoài tầm với của sockops.
4. **Implication cho architecture:** Microservices giao tiếp nhiều → đặt cùng node → tự động hưởng sockops 6-10x speedup. Pod affinity rules + Cilium sockops = performance win không cần code thay đổi.
