# Lab Tập 6: Cài đặt và Quan sát Flannel CNI (VXLAN Mode)

Trong bài lab này, chúng ta sẽ bắt đầu bằng một cluster trắng (chưa có CNI) để thấy rõ sự bế tắc của các Pod khi không có định tuyến cross-node. Sau đó, chúng ta sẽ cài Flannel và quan sát cách nó tháo gỡ vấn đề bằng VXLAN tunnel.

## 🛠 Yêu cầu chuẩn bị
- Cụm Kubernetes 3 node (controlplane, worker1, worker2) từ Tập 00.
- **Nếu cụm đang cài sẵn Flannel từ Tập 1**: Bạn có thể giữ nguyên và bỏ qua Bước 1. Hoặc nếu muốn làm lại từ đầu để hiểu sâu hơn, hãy chạy script dọn dẹp `./reset-lab.sh` ở thư mục `tap-00-setup-lab` và dựng lại cụm trắng.

---

## 🔬 Thí nghiệm 1: Quan sát Cluster khi KHÔNG có Flannel

Giả sử bạn đang có một cụm trắng (chưa cài đặt CNI).

1. SSH vào `controlplane`:
   ```bash
   multipass shell controlplane
   ```

2. Kiểm tra trạng thái Nodes:
   ```bash
   kubectl get nodes
   ```
   *Nhận xét:* Nodes ở trạng thái `NotReady`.

3. Kiểm tra bảng định tuyến trên `worker1` (mở terminal mới):
   ```bash
   multipass shell worker1
   ip route show
   ```
   *Nhận xét:* Không hề có các route chỉ đường cho dải mạng Pod (ví dụ `10.244.x.x`).

---

## 🚀 Thí nghiệm 2: Cài đặt Flannel và quan sát sự thay đổi

**Trên Terminal đang SSH vào `controlplane`:**

1. Cài đặt Flannel CNI (phiên bản mới nhất):
   ```bash
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

2. Theo dõi trạng thái Cluster. Chờ đến khi tất cả các node chuyển sang `Ready`:
   ```bash
   watch kubectl get nodes
   ```
   *(Nhấn Ctrl+C để thoát)*

**Trên Terminal đang SSH vào `worker1`:**

3. Quan sát các card mạng ảo mới xuất hiện:
   ```bash
   ip link show
   ```
   *Nhận xét:* Bạn sẽ thấy sự xuất hiện của `cni0` (bridge cho Pod) và `flannel.1` (giao diện VTEP phục vụ cho việc bọc gói tin VXLAN).

4. Quan sát bảng định tuyến (Routing table):
   ```bash
   ip route show
   ```
   *Nhận xét:* Lúc này các route `10.244.0.0/24 via 10.244.0.0 dev flannel.1` đã được tự động thêm vào, cho phép traffic biết đường đi sang các node khác thông qua interface `flannel.1`.

---

## 🌐 Thí nghiệm 3: Kiểm chứng kết nối Cross-Node

**Trên Terminal đang SSH vào `controlplane`:**

1. Khởi tạo 2 Pod nằm trên 2 Worker khác nhau:
   ```bash
   kubectl run pod-a --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker1"}}' -- sleep infinity
   kubectl run pod-b --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker2"}}' -- sleep infinity
   ```

2. Chờ 2 Pod chạy và lấy IP của chúng:
   ```bash
   kubectl wait --for=condition=Ready pod/pod-a pod/pod-b --timeout=60s
   kubectl get pods -o wide
   ```
   *Giả sử IP của Pod B là `10.244.2.X`.*

3. Đứng từ `pod-a`, thực hiện lệnh `ping` sang IP của `pod-b`:
   ```bash
   kubectl exec pod-a -- ping -c 3 <IP_CỦA_POD_B>
   ```
   *Kết quả:* Ping thành công rực rỡ! Gói tin của bạn đã được `flannel.1` đóng gói lại thành các UDP packet (VXLAN) và vận chuyển an toàn qua lại giữa 2 Node vật lý ảo.

---

## ✅ Tổng kết

Flannel là một trong những CNI đơn giản nhất. Nó giải bài toán Cross-Node bằng cách tạo ra một mạng overlay (mạng phẳng) thông qua VXLAN. Tuy nhiên, nó chỉ làm đúng nhiệm vụ cấp mạng và định tuyến chứ KHÔNG hỗ trợ bảo mật (Network Policies).
