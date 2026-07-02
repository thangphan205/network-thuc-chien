# Lab Tập 27: Cùng Node vs Khác Node — Đo latency và trace packet paths

Tập này deploy 4 pods để có 2 scenarios (same-node và cross-node), đo latency + bandwidth thực tế, và verify cơ chế **BPF host-routing** (`bpf_redirect_peer()`) tăng tốc same-node traffic.

> **💡 Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** tính năng `sockops` (TCP socket-splice bypass hoàn toàn network stack) đã bị **loại bỏ từ v1.14** — grep source v1.19.5 cho `sockops`/`sockmap` ra 0 kết quả. Cơ chế same-node speedup thật sự trong bản hiện tại là **BPF host-routing**: TC BPF program tra map `cilium_lxc` để biết đích có phải pod local không, nếu có thì gọi `bpf_redirect_peer()`/`bpf_redirect_neigh()` để nhảy thẳng sang veth peer — **vẫn đi qua veth và TC BPF**, chỉ bỏ qua iptables/netfilter (và với cross-node, bỏ luôn VXLAN encap + NIC vật lý). Field xác nhận cơ chế này đang bật: `Routing: ... Host: BPF` trong `cilium status --verbose`.

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy với BPF host-routing (mặc định từ v1.9+, verify qua `cilium status --verbose | grep Routing`).
- Cluster có worker1 và worker2 đang sẵn sàng.
- `iperf3` có sẵn trong image `nicolaka/netshoot`.

---

## 🔬 Thực nghiệm 1: Deploy 4 pods cho 2 scenarios

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

## 🔬 Thực nghiệm 2: Đo latency — same-node vs cross-node

**Trên `controlplane`:**

1. **Latency — same-node (BPF host-routing, `bpf_redirect_peer`):**
   ```bash
   kubectl exec same-client -- ping -c 50 $SAME_IP | tail -3
   # 50 packets transmitted, 50 received, 0% packet loss
   # rtt min/avg/max/mdev = 0.048/0.062/0.089/0.008 ms
   # ← ~0.05-0.1ms: vẫn qua veth + TC BPF nhưng bỏ qua iptables/netfilter
   ```

2. **Latency — cross-node (TC + VXLAN + physical NIC):**
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

   *Nhận xét:* ICMP ping same-node đi qua `bpf_redirect_peer()` (BPF host-routing) — vẫn qua veth + TC BPF nhưng bỏ qua iptables/netfilter nên nhanh hơn đáng kể so với path cross-node phải qua thêm VXLAN encap + NIC vật lý.

---

## 💥 Thực nghiệm 3: Đo bandwidth — same-node vs cross-node

**Trên `controlplane`:**

1. **Bandwidth — same-node (BPF host-routing):**
   ```bash
   kubectl exec same-client -- iperf3 -c $SAME_IP -t 10 -P 4
   # [SUM] 0.00-10.00 sec  23.0 GBytes  18.4 Gbits/sec  sender
   # ← Nhanh hơn nhiều: bỏ qua iptables/netfilter, vẫn qua veth + TC BPF
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

## 🔬 Thực nghiệm 4: Verify BPF host-routing đang active

**Trên `controlplane`:**

> **💡 Lưu ý:** `cilium bpf metrics list` chỉ có 2 nhóm REASON thật — `Success` (packet forward) và các mã DROP cụ thể (`Policy denied`...). Không có counter riêng phân biệt "forward qua same-node fast path" vs "forward qua path thường" — CLI không expose chi tiết đó. Bằng chứng thực nghiệm cho BPF host-routing là **latency/bandwidth đo được ở TN2/TN3**, kết hợp với 2 bước static-check dưới đây.

1. Lấy cilium-agent pod trên worker1 (nơi same-client chạy):
   ```bash
   WORKER1_CILIUM=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium \
     --field-selector spec.nodeName=worker1 \
     -o name | head -1)
   echo "Cilium pod trên worker1: $WORKER1_CILIUM"
   ```

2. Verify BPF host-routing đang bật cho same-node (field `Routing`):
   ```bash
   kubectl -n kube-system exec -it $WORKER1_CILIUM -- \
     cilium status --verbose | grep "Routing:"
   # Routing:   Network: native   Host: BPF
   # ← "Host: BPF" nghĩa là bpf_redirect_peer()/bpf_redirect_neigh() đang active cho same-node.
   # Nếu thấy "Host: Legacy" thì same-node traffic vẫn đi qua full netfilter stack (chậm hơn).
   ```

3. Verify cilium_lxc map — chỉ chứa Pods trên worker1:
   ```bash
   kubectl -n kube-system exec -it $WORKER1_CILIUM -- \
     cilium bpf endpoint list
   # IP ADDRESS           LOCAL ENDPOINT INFO
   # 10.244.1.5           id=1234 ifindex=22 mac=xx:xx:xx:xx:xx:xx nodemac=yy:yy  ← same-server (worker1)
   # 10.244.1.8           id=2345 ifindex=24 mac=yy:yy:yy:yy:yy:yy nodemac=zz:zz  ← same-client (worker1)
   # ← cross-server (10.244.2.x) KHÔNG có ở đây → TC BPF không thể redirect trực tiếp
   ```

   *Nhận xét:* `cilium_lxc` chỉ có Pods của node hiện tại → khi TC BPF program (`bpf_lxc.c`) tra map này với IP đích là `cross-server`, kết quả là lookup-miss → gói tin phải đi tiếp qua routing table bình thường → VXLAN encap → NIC vật lý, thay vì được `bpf_redirect_peer()` chuyển thẳng sang veth peer như trường hợp same-node.

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod same-server same-client cross-server cross-client
```

---

## ✅ Tổng kết

1. **Same-node path (BPF host-routing):** Packet qua veth → TC BPF (`bpf_lxc.c`) tra map `cilium_lxc` → tìm thấy đích là pod local → gọi `bpf_redirect_peer()`/`bpf_redirect_neigh()` chuyển thẳng sang veth peer → ~0.05ms, ~18 Gbps. Vẫn qua veth + TC BPF, chỉ bỏ qua iptables/netfilter.
2. **Cross-node path (TC + encap):** Lookup `cilium_lxc` miss (đích không phải pod local) → packet đi tiếp qua routing table → TC BPF (policy check) → VXLAN encap → physical NIC → ~0.35ms, ~2 Gbps (network-bound).
3. **Tại sao same-node path không dùng được cho cross-node:** `bpf_redirect_peer()` chỉ hoạt động khi biết chính xác veth peer (ifindex) của đích — thông tin này chỉ có trong `cilium_lxc` cho pod local. Cross-node cần encapsulation (VXLAN) và định tuyến qua NIC vật lý, việc mà TC BPF layer không thể "redirect tắt" được.
4. **Implication cho architecture:** Microservices giao tiếp nhiều → đặt cùng node (pod affinity) → tự động hưởng BPF host-routing fast path, thường nhanh hơn đáng kể so với cross-node — không cần code thay đổi, chỉ cần scheduling hint.
