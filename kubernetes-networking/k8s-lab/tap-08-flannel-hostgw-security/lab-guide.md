# Lab Tập 8: Định tuyến host-gw Mode trên Flannel CNI & Khắc phục Sự cố

Trong bài lab này, chúng ta sẽ bắt đầu bằng việc chuyển đổi Flannel từ VXLAN (Overlay) sang host-gw (Direct Routing) để đo đạc và so sánh trực quan hiệu năng truyền dữ liệu. Tiếp theo, chúng ta sẽ thực hành các kịch bản lỗi định tuyến nâng cao và tiến hành khắc phục sự cố trực tiếp trên các Node (card ảo flannel.1 cũ tồn đọng và tường lửa Host chặn forwarding).

---

## 🧭 So sánh Kỹ thuật: VXLAN vs host-gw Mode

| Tiêu chí | VXLAN Mode (Overlay) | host-gw Mode (Underlay/Direct Routing) |
|---|---|---|
| **Cơ chế hoạt động** | Đóng gói L2 frame trong UDP packet (cổng 8472) chui qua tunnel. | Định tuyến trực tiếp L3 dựa vào Kernel routing table trên Host. |
| **Overhead gói tin** | Có (50 bytes VXLAN header bọc ngoài). | Không (0 byte overhead, packet được giữ nguyên bản). |
| **MTU của Pod** | Bị giới hạn ở `1450` bytes (nếu MTU Host = 1500). | Đạt tối đa `1500` bytes (bằng với MTU Host vật lý). |
| **Hiệu năng CPU** | Cao hơn (Kernel phải liên tục bọc/gỡ gói tin ở tầng phần mềm). | Rất thấp (Kernel định tuyến trực tiếp bằng bảng route phần cứng/kernel). |
| **Throughput & Latency** | Baseline (Chậm hơn 10 - 15%, Latency cao hơn do overhead đóng gói). | Tối ưu (Nhanh hơn, Latency thấp hơn khoảng 30 - 35% so với VXLAN). |
| **Điều kiện hạ tầng** | Nodes có thể nằm ở các Subnet vật lý khác nhau (miễn là thông UDP 8472). | **Bắt buộc** các Node phải cùng thuộc mạng L2 (Direct L2 connectivity). |

---

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Flannel VXLAN đang chạy (từ Tập 6 - 7).
- Tất cả 3 Nodes phải cùng L2 network (môi trường Multipass mặc định đáp ứng điều này).

---

## 🚀 Thực nghiệm 1: Chuyển đổi từ VXLAN sang host-gw

**SSH vào `controlplane`:**

1. Xem config Flannel hiện tại (VXLAN):
   ```bash
   kubectl -n kube-flannel get configmap kube-flannel-cfg -o jsonpath='{.data.net-conf\.json}' | python3 -m json.tool
   ```

2. Patch ConfigMap để chuyển sang backend `host-gw`:
   ```bash
   kubectl -n kube-flannel patch configmap kube-flannel-cfg \
     --type=json \
     -p='[{"op": "replace", "path": "/data/net-conf.json", "value": "{\"Network\": \"10.244.0.0/16\", \"Backend\": {\"Type\": \"host-gw\"}}"}]'
   ```

3. Restart flanneld DaemonSet để áp dụng cấu hình mới:
   ```bash
   kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds
   kubectl -n kube-flannel rollout status daemonset kube-flannel-ds
   ```

---

## 🚀 Thực nghiệm 2: Kiểm tra định tuyến và MTU trên worker1

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. **⚠️ Dọn dẹp thủ công:** Tiến trình `flanneld` ở chế độ `host-gw` không sử dụng thiết bị ảo VXLAN. Tuy nhiên, nó sẽ **bỏ qua** chứ không tự động xóa interface `flannel.1` cũ kẹt trong kernel. Ta cần xóa thủ công:
   ```bash
   sudo ip link delete flannel.1
   ```

2. Kiểm tra routing table mới:
   ```bash
   ip route show | grep 10.244
   ```
   *Kết quả mong đợi:*
   ```
   10.244.0.0/24 via 192.168.64.10 dev eth0   ← Định tuyến trực tiếp tới controlplane
   10.244.1.0/24 dev cni0                     ← Subnet Pod local trên worker1
   10.244.2.0/24 via 192.168.64.12 dev eth0   ← Định tuyến trực tiếp tới worker2
   ```
   *Nhận xét:* Không còn card `flannel.1` làm gateway. Mọi traffic chéo node được chuyển trực tiếp qua cổng vật lý `eth0`.

3. Kiểm tra MTU của bridge:
   ```bash
   ip link show cni0 | grep mtu
   ```
   *Kết quả:* `mtu 1500` — Tăng lên 1500! Pod bây giờ được hưởng đầy đủ MTU nguyên bản mà không bị hao hụt 50 bytes tunnel overhead.

---

## 🚀 Thực nghiệm 3: Benchmark throughput với iperf3

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
   
   kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/iperf3-client --timeout=60s
   kubectl logs iperf3-client | tail -5
   ```
   *Nhận xét:* So sánh kết quả throughput với baseline ở Tập 7 (VXLAN). Bạn sẽ thấy throughput ở `host-gw` tăng khoảng 10 - 15% và latency giảm rõ rệt.
3. Dọn dẹp:
   ```bash
   kubectl delete pod iperf3-client iperf3-server
   kubectl delete svc iperf3-server
   ```

---

## ✅ Tổng kết

1. `host-gw` mang lại hiệu năng cao nhất cho Flannel nhờ cơ chế định tuyến trực tiếp L3, đạt full MTU 1500 và loại bỏ hoàn toàn CPU đóng/giải gói.
2. Điểm hạn chế lớn nhất của host-gw mode là yêu cầu khắt khe về topology hạ tầng mạng: tất cả các Node bắt buộc phải cùng thuộc một mạng L2 (Direct L2 connectivity) thì mới có thể định tuyến trực tiếp chéo Node.
3. Thông qua các kịch bản khắc phục sự cố định tuyến chéo Node, bạn đã nắm vững cách hoạt động của bảng route nhân Linux và tầm ảnh hưởng của Host Firewall (chuỗi FORWARD chain) đối với các CNI định tuyến trực tiếp (Direct Routing).
