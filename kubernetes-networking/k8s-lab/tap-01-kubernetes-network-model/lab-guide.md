# Lab Tập 1: Kubernetes Network Model & Tầm quan trọng của CNI

Ở bài lab này, chúng ta sẽ quan sát cụm Kubernetes ở trạng thái "nguyên thủy" (chưa cài đặt CNI) để hiểu rõ tại sao K8s lại cần CNI và hậu quả khi không có mạng. Sau đó, chúng ta sẽ cài đặt Flannel CNI và quan sát sự thay đổi của network interfaces cũng như bảng định tuyến (routing table) trên các Node.

## 🛠 Yêu cầu chuẩn bị
- Cụm Kubernetes 3 node đã được khởi tạo xong theo **Tập 00** (sử dụng `./setup-lab.sh`).
- Cụm **chưa** được cài đặt bất kỳ CNI nào (ví dụ: Flannel, Calico, Cilium).

---

## 🔬 Thí nghiệm 1: Trạng thái "Vô danh" của Cluster

1. Mở Terminal và kiểm tra trạng thái của các Nodes thông qua `controlplane`:
   ```bash
   multipass exec controlplane -- kubectl get nodes
   ```
   *Kết quả mong đợi:* Cả 3 nodes đều ở trạng thái `NotReady`. Kubelet đang chờ CNI plugin.

2. Cố gắng tạo một Pod xem điều gì sẽ xảy ra:
   ```bash
   multipass exec controlplane -- kubectl run test-pod --image=nginx
   multipass exec controlplane -- kubectl get pod test-pod
   ```
   *Kết quả mong đợi:* Pod sẽ ở trạng thái `Pending` mãi mãi vì Scheduler không thể gán Pod vào bất kỳ Node nào (do Node NotReady).

3. Vào shell của Node `controlplane` để xem lý do chi tiết:
   ```bash
   multipass shell controlplane
   kubectl describe node controlplane | grep -A5 Conditions
   ```
   *Bạn sẽ thấy thông báo: `NetworkPluginNotReady message: network plugin is not ready: cni config uninitialized`*

4. Kiểm tra Network Interfaces và Bảng định tuyến (routing table) ở mức hệ điều hành (chạy trong shell của `controlplane`):
   ```bash
   ip link show
   ip route show
   ```
   *Nhận xét:* Bạn chỉ thấy các card mạng vật lý/ảo cơ bản (như `eth0`, `lo`). Không hề có card mạng ảo nào phục vụ cho Pod (như `cni0` hay `flannel.1`). Không có route nào dẫn đến dải mạng của Pod (`10.244.x.x`).

Thoát khỏi shell của `controlplane` bằng lệnh `exit`.

---

## 🚀 Thí nghiệm 2: Cấp mạng cho Cluster bằng Flannel CNI

Chúng ta sẽ cài đặt Flannel, một CNI rất đơn giản và phổ biến dùng cơ chế VXLAN.

1. Cài đặt Flannel từ máy host (nếu bạn đã lấy kubeconfig về máy) hoặc từ `controlplane`:
   ```bash
   multipass exec controlplane -- kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

2. Theo dõi trạng thái Cluster thay đổi. Các Node sẽ lần lượt chuyển sang `Ready`:
   ```bash
   multipass exec controlplane -- kubectl get nodes -w
   ```
   *Bấm `Ctrl+C` để thoát khi cả 3 node đã `Ready`.*

3. Kiểm tra lại trạng thái của Pod `test-pod` vừa nãy:
   ```bash
   multipass exec controlplane -- kubectl get pod test-pod
   ```
   *Bây giờ Pod đã chuyển sang `Running` vì Node đã sẵn sàng, và Pod đã được cấp 1 địa chỉ IP trong dải `10.244.x.x`.*

---

## 🕵️‍♂️ Thí nghiệm 3: "Dấu vết" của CNI để lại

1. Vào lại shell của `controlplane`:
   ```bash
   multipass shell controlplane
   ```

2. Xem sự xuất hiện của các Card mạng ảo mới:
   ```bash
   ip link show
   ```
   *Phát hiện:*
   - `flannel.1`: Thiết bị VTEP (VXLAN Tunnel Endpoint) dùng để đóng gói gói tin gửi sang Node khác.
   - `cni0`: Một virtual bridge. Kubelet gắn các veth-pair của các Pod trên node này vào bridge `cni0`.

3. Kiểm tra Bảng định tuyến (Routing table):
   ```bash
   ip route show
   ```
   *Phân tích:*
   - `10.244.0.0/24 dev cni0 ...`: Bất kỳ request nào gửi đến IP của Pod nằm trên *chính Node này* sẽ được đẩy vào bridge `cni0`.
   - `10.244.1.0/24 via 10.244.1.0 dev flannel.1 ...`: Request gửi đến dải IP Pod của *worker1* sẽ bị đẩy qua cổng `flannel.1` (để bọc VXLAN header rồi gửi sang mạng vật lý).
   - `10.244.2.0/24 via 10.244.2.0 dev flannel.1 ...`: Tương tự cho *worker2*.

---

## ✅ Tổng kết

Bạn vừa chứng kiến quy trình hoàn thiện một cụm Kubernetes. CNI plugin không phải là phép màu, nó thực chất chỉ là một tiến trình tự động thực hiện các thao tác Linux cơ bản: **tạo virtual network interfaces (cni0, flannel.1)** và **thêm các rules vào bảng định tuyến (routing table)** để đảm bảo tuân thủ 4 nguyên tắc Kubernetes Network Model.

