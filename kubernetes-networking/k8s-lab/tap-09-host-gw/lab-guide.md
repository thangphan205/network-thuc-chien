# Lab Tập 9: host-gw Mode — Switch từ VXLAN và Benchmark

Tập này chứng minh bằng thực nghiệm rằng host-gw mode nhanh hơn VXLAN. Bạn sẽ tự tay switch Flannel config, quan sát `flannel.1` biến mất, và đo throughput bằng `iperf3`.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Flannel VXLAN đang chạy (Tập 8).
- Tất cả 3 Nodes phải cùng L2 network (Multipass đảm bảo điều này).

---

## 🚀 Thí nghiệm 1: Switch từ VXLAN sang host-gw

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Xem config Flannel hiện tại (VXLAN):
   ```bash
   kubectl -n kube-flannel get configmap kube-flannel-cfg \
     -o jsonpath='{.data.net-conf\.json}' | python3 -m json.tool
   ```
   *Kết quả:*
   ```json
   {
     "Network": "10.244.0.0/16",
     "Backend": {
       "Type": "vxlan"
     }
   }
   ```

2. Patch ConfigMap để chuyển sang host-gw:
   ```bash
   kubectl -n kube-flannel patch configmap kube-flannel-cfg \
     --type=json \
     -p='[{"op": "replace", "path": "/data/net-conf.json", "value": "{\"Network\": \"10.244.0.0/16\", \"Backend\": {\"Type\": \"host-gw\"}}"}]'
   ```
   *Verify:*
   ```bash
   kubectl -n kube-flannel get configmap kube-flannel-cfg \
     -o jsonpath='{.data.net-conf\.json}'
   # {"Network": "10.244.0.0/16", "Backend": {"Type": "host-gw"}}
   ```

3. Restart flanneld DaemonSet để apply config mới:
   ```bash
   kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds
   kubectl -n kube-flannel rollout status daemonset kube-flannel-ds
   ```
   *Chờ đến khi tất cả Pods restart xong (~30 giây).*

---

## 🔬 Thí nghiệm 2: Quan sát sự thay đổi trên worker1

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Kiểm tra `flannel.1` đã biến mất chưa:
   ```bash
   ip link show | grep flannel
   ```
   *Kết quả mong đợi:* **Không có output** — `flannel.1` đã bị xóa hoàn toàn! VTEP không cần thiết nữa vì không có encapsulation.

2. Kiểm tra routing table mới:
   ```bash
   ip route show | grep 10.244
   ```
   *Kết quả:*
   ```
   10.244.0.0/24 via 192.168.64.10 dev eth0   ← Route thẳng đến controlplane
   10.244.1.0/24 dev cni0                     ← Local subnet
   10.244.2.0/24 via 192.168.64.12 dev eth0   ← Route thẳng đến worker2
   ```
   *Nhận xét:* Routes giờ chỉ đến `eth0` (physical), không còn `flannel.1` (tunnel). Mỗi Node bây giờ hoạt động như một router biết cách forward Pod traffic.

3. Kiểm tra MTU của bridge:
   ```bash
   ip link show cni0 | grep mtu
   ```
   *Kết quả:* `cni0: mtu 1500` — Tăng từ 1450 lên 1500! Pod giờ có full MTU.

---

## 🔬 Thí nghiệm 3: Verify bằng tcpdump — không còn UDP 8472

**Mở 2 terminal:**

**Terminal 1 — `worker1`, bắt traffic:**
```bash
multipass shell worker1

# Nghe cả VXLAN (8472) và ICMP thẳng
sudo tcpdump -i eth0 -n '(udp port 8472) or icmp'
```

**Terminal 2 — `controlplane`, tạo traffic:**
```bash
multipass shell controlplane
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
kubectl exec pod-a -- ping -c 5 $POD_B_IP
```

**Quay lại Terminal 1:**
- Sẽ **không thấy** dòng `> 8472: VXLAN` nào
- Thay vào đó thấy ICMP trực tiếp:
  ```
  12:35:00 IP 10.244.1.5 > 10.244.2.7: ICMP echo request
  ```
*Nhận xét:* Packet không bị bọc trong UDP nữa — source IP là Pod IP thật, không phải Node IP.

Bấm `Ctrl+C` để dừng tcpdump.

---

## 🏁 Thí nghiệm 4: Benchmark throughput với iperf3

**Trên `controlplane`:**

1. Deploy iperf3 server trên `worker2`:
   ```bash
   kubectl run iperf3-server \
     --image=networkstatic/iperf3 \
     --overrides='{"spec":{"nodeName":"worker2"}}' \
     -- iperf3 -s
   kubectl expose pod iperf3-server --port=5201 --type=ClusterIP
   kubectl wait --for=condition=Ready pod/iperf3-server --timeout=60s
   ```

2. Test throughput từ `worker1` (cross-node) — **host-gw mode hiện tại:**
   ```bash
   IPERF_IP=$(kubectl get svc iperf3-server -o jsonpath='{.spec.clusterIP}')

   kubectl run iperf3-client \
     --image=networkstatic/iperf3 \
     --overrides='{"spec":{"nodeName":"worker1"}}' \
     --restart=Never \
     -- iperf3 -c $IPERF_IP -t 15 -P 4

   kubectl wait --for=condition=Ready pod/iperf3-client --timeout=60s
   kubectl logs iperf3-client | tail -5
   ```
   *Ghi lại kết quả throughput (Gbits/sec).*

3. Test latency:
   ```bash
   kubectl exec iperf3-client -- ping -c 50 $IPERF_IP 2>/dev/null | tail -2
   ```

4. Dọn dẹp:
   ```bash
   kubectl delete pod iperf3-client iperf3-server
   kubectl delete svc iperf3-server
   ```

> **So sánh kỳ vọng:** Nếu bạn đã benchmark ở Tập 8 (VXLAN), host-gw thường nhanh hơn 10-15% throughput và latency thấp hơn ~30-35%. Kết quả thực tế phụ thuộc vào phần cứng Multipass host.

---

## ✅ Tổng kết

1. Chuyển VXLAN → host-gw chỉ cần **patch 1 ConfigMap + restart DaemonSet**.
2. Hiệu quả rõ: `flannel.1` biến mất, MTU tăng 1450→1500, không còn UDP 8472.
3. Điều kiện cứng: **phải cùng L2 segment** — đây là lý do host-gw không dùng được trên cloud multi-subnet.
4. Trên Multipass (L2 bridged), host-gw là lựa chọn tốt hơn VXLAN cho lab performance.

---

## 🔄 Khôi phục về VXLAN (chuẩn bị cho Tập 10)

Tập 10 không yêu cầu mode cụ thể. Nếu muốn giữ host-gw, không cần làm gì. Nếu muốn về VXLAN:
```bash
kubectl -n kube-flannel patch configmap kube-flannel-cfg \
  --type=json \
  -p='[{"op": "replace", "path": "/data/net-conf.json", "value": "{\"Network\": \"10.244.0.0/16\", \"Backend\": {\"Type\": \"vxlan\"}}"}]'
kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds
```
