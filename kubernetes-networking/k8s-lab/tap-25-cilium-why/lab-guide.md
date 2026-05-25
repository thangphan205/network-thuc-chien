# Lab Tập 25: Tại sao Cilium? — Cài đặt và đo latency sockops

Tập này cài Cilium thay thế CNI cũ, verify sockops active, và đo thực tế latency khác biệt giữa same-node (sockops bypass) và cross-node.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s 3 node (controlplane, worker1, worker2) — không có CNI hoặc sẽ thay thế CNI cũ.
- Helm đã cài trên controlplane.
- Ít nhất 3GB RAM trống trên cluster.

---

## 🔬 Thí nghiệm 1: Cài Cilium qua Helm

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Thêm Cilium Helm repo:
   ```bash
   helm repo add cilium https://helm.cilium.io/
   helm repo update
   helm search repo cilium/cilium --versions | head -5
   ```

2. Cài Cilium với sockops và Hubble enabled:
   ```bash
   helm install cilium cilium/cilium \
     --namespace kube-system \
     --set socketLB.enabled=true \
     --set hubble.enabled=true \
     --set hubble.relay.enabled=true \
     --set hubble.ui.enabled=true \
     --set ipam.mode=kubernetes
   ```

3. Chờ Cilium pods sẵn sàng:
   ```bash
   kubectl -n kube-system wait \
     --for=condition=Ready pod -l k8s-app=cilium \
     --timeout=120s
   kubectl -n kube-system get pods -l k8s-app=cilium
   # NAME            READY   STATUS    NODE
   # cilium-xxxxx    1/1     Running   controlplane
   # cilium-yyyyy    1/1     Running   worker1
   # cilium-zzzzz    1/1     Running   worker2
   ```

4. Kiểm tra nodes Ready:
   ```bash
   kubectl get nodes
   # Tất cả phải STATUS=Ready sau khi Cilium cài xong
   ```

---

## 🔬 Thí nghiệm 2: Verify sockops active

**Trên `controlplane`:**

1. Xem Cilium status tổng quan:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- cilium status
   # Output:
   # Cilium:     OK
   # BPF:        OK
   # Sockops:    Enabled  ← Key indicator!
   # Hubble:     OK
   ```

2. Verify BPF programs được load:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -E "name|type" | grep -A1 "sock"
   # 45: sock_ops  name bpf_sockops  ← sockops program in kernel
   # 46: sk_msg    name bpf_redir_proxy
   ```

3. Xem tất cả BPF programs Cilium đang dùng:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -c "cilium\|bpf_sock"
   # Số lượng programs loaded (thường 20-50)
   ```

   *Nhận xét:* `sock_ops` program chạy trong kernel intercepts mọi TCP `connect()` syscall để detect same-node traffic.

---

## 💥 Thí nghiệm 3: So sánh latency same-node vs cross-node

**Trên `controlplane`:**

1. Deploy iperf3 server trên **worker1** (same-node test):
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

2. Deploy iperf3 server trên **worker2** (cross-node test):
   ```bash
   kubectl run cross-server \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker2"}}' \
     -- iperf3 -s -B 0.0.0.0

   kubectl run cross-client \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker1"}}' \
     -- sleep infinity

   kubectl wait --for=condition=Ready \
     pod/same-server pod/same-client \
     pod/cross-server pod/cross-client \
     --timeout=90s
   ```

3. Lấy IPs:
   ```bash
   SAME_IP=$(kubectl get pod same-server -o jsonpath='{.status.podIP}')
   CROSS_IP=$(kubectl get pod cross-server -o jsonpath='{.status.podIP}')
   echo "Same-node server IP: $SAME_IP"
   echo "Cross-node server IP: $CROSS_IP"
   ```

---

## 🔬 Thí nghiệm 4: Đo và so sánh kết quả

**Trên `controlplane`:**

1. **Latency test — same-node (sockops bypass):**
   ```bash
   kubectl exec same-client -- ping -c 50 $SAME_IP | tail -2
   # rtt min/avg/max/mdev = 0.048/0.062/0.089/0.008 ms
   # ← ~0.05-0.1ms: gần như loopback speed
   ```

2. **Latency test — cross-node (TC + encapsulation):**
   ```bash
   kubectl exec cross-client -- ping -c 50 $CROSS_IP | tail -2
   # rtt min/avg/max/mdev = 0.280/0.350/0.450/0.032 ms
   # ← ~0.3-0.5ms: network-bound
   ```

3. **Bandwidth test — same-node:**
   ```bash
   kubectl exec same-client -- iperf3 -c $SAME_IP -t 10 -P 4
   # [SUM] 18.4 Gbits/sec  ← Near-loopback speed (sockops)
   ```

4. **Bandwidth test — cross-node:**
   ```bash
   kubectl exec cross-client -- iperf3 -c $CROSS_IP -t 10 -P 4
   # [SUM] 2.1 Gbits/sec   ← Network-bound (physical NIC limit)
   ```

5. Verify sockops metrics tăng sau same-node test:
   ```bash
   WORKER1_CILIUM=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium --field-selector spec.nodeName=worker1 \
     -o name | head -1)

   kubectl -n kube-system exec -it $WORKER1_CILIUM -- \
     cilium bpf metrics list | grep -i "sock\|redirect"
   # Forwarded via sockops: X packets  ← Tăng sau test
   ```

   *Tổng kết thực nghiệm:*
   - Same-node (sockops): ~0.05ms, ~18 Gbps
   - Cross-node (TC): ~0.35ms, ~2 Gbps
   - Ratio: 6-10x nhanh hơn về latency, 8x về bandwidth

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod same-server same-client cross-server cross-client
```

---

## ✅ Tổng kết

1. **iptables O(n) là giới hạn thực:** Cluster 5000 nodes + 100k policies → Calico mất 45 phút update rules. Cilium BPF maps: dưới 1 giây.
2. **sockops = kernel-level shortcut:** BPF program intercept TCP `connect()` syscall → nếu dst Pod cùng node → redirect socket-to-socket, bỏ qua toàn bộ TCP stack + veth + iptables.
3. **Hubble built-in:** Không cần setup tcpdump hay log parser thủ công — `hubble observe --verdict DROPPED` cho ngay flow nào bị deny và tại sao.
4. **Kết quả đo thực tế:** Same-node sockops ~0.05ms / ~18 Gbps vs cross-node TC ~0.35ms / ~2 Gbps — sự khác biệt đủ lớn để ảnh hưởng architecture quyết định pod placement.
