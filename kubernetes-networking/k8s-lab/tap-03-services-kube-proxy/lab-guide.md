# Lab Tập 3: Services & kube-proxy (iptables)

Ở Tập 2, chúng ta đã biết cách Pod giao tiếp qua IP thực của nó. Nhưng IP của Pod rất "dễ bay màu" (khi Pod bị xóa, IP sẽ thay đổi). Do đó, Kubernetes đẻ ra khái niệm **Service** (VIP - Virtual IP) làm mặt tiền cố định.

Bài lab này sẽ giúp bạn dùng "kính lúp" soi vào bên trong `kube-proxy` để xem làm thế nào một cái IP ẢO (ClusterIP) lại có thể tự động bẻ lái (DNAT) traffic vào đúng các IP THẬT của Pod.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s 3 node đã cài CNI Flannel (Kết quả từ Tập 1).

---

## 🚀 Thí nghiệm 1: Bí ẩn của ClusterIP (Ping vs Curl)

**Trên Terminal đang SSH vào `controlplane`:**

1. Tạo một ứng dụng Nginx gồm 3 bản sao (replicas):
   ```bash
   kubectl create deployment nginx --image=nginx --replicas=3
   ```

2. Tạo mặt tiền (Service) cho Nginx bằng IP Ảo (ClusterIP):
   ```bash
   kubectl expose deployment nginx --port=80 --type=ClusterIP
   ```

3. Lấy thông tin ClusterIP vừa được tạo ra:
   ```bash
   kubectl get svc nginx
   ```
   *Giả sử ClusterIP của bạn là `10.96.123.45`.*

4. Thử `ping` vào ClusterIP này:
   ```bash
   ping -c 3 10.96.123.45
   ```
   *Kết quả:* **Timeout!** Gói tin không đi đến đâu cả.

5. Thử `curl` vào ClusterIP này:
   ```bash
   curl -s http://10.96.123.45
   ```
   *Kết quả:* **Thành công rực rỡ!** Nginx trả về mã HTML.

> **🤔 Tại sao?** 
> ClusterIP không phải là một card mạng thật, nó CHỈ TỒN TẠI trong bảng luật `iptables`. Kube-proxy cấu hình `iptables` chỉ bắt (match) các gói tin **TCP/UDP** có đúng số Port (80). Gói tin `ping` là giao thức ICMP, nên `iptables` bỏ qua, dẫn đến Timeout.

---

## 🔬 Thí nghiệm 2: Lần theo dấu vết Iptables

Bây giờ chúng ta sẽ chui xuống `worker1` để xem `kube-proxy` đã "phù phép" bảng iptables ra sao.

**Trên Terminal đang SSH vào `controlplane`:**

1. Lấy danh sách IP thật của 3 Pod Nginx (Endpoints) để ghi nhớ:
   ```bash
   kubectl get endpoints nginx
   ```

**Sau đó, chuyển sang Terminal đang SSH vào `worker1`:**

2. Truy tìm luật iptables bắt đầu từ chuỗi `KUBE-SERVICES`:
   ```bash
   # Nhớ thay IP dưới đây bằng ClusterIP thật của bạn nhé
   sudo iptables -t nat -L KUBE-SERVICES -n | grep 10.96.123.45
   ```
   *Kết quả:* Sẽ có một luật nói rằng: Bất cứ ai gọi đến `10.96.123.45:80` thì hãy nhảy vào chuỗi **`KUBE-SVC-xxxxxxxx`**. (Copy cái tên chuỗi này lại).

3. Xem cách K8s chia tải ngẫu nhiên bằng thuộc tính `statistic mode random`:
   ```bash
   sudo iptables -t nat -L KUBE-SVC-xxxxxxxx -n
   ```
   *Nhận xét:* Bạn sẽ thấy 3 dòng, tương ứng với 3 nhánh rẽ (KUBE-SEP-...). Xác suất rẽ nhánh đầu tiên là `0.33` (33%), nhánh thứ hai là `0.5` (50% của 66% còn lại), và nhánh cuối cùng là vét máng. Đây chính là thuật toán Round-Robin của iptables!

4. Xem cách IP ảo bị biến thành IP thật (DNAT - Destination NAT):
   ```bash
   sudo iptables -t nat -L KUBE-SEP-yyyyyyyy -n
   ```
   *Kết quả:* Dòng `DNAT` lộ diện rõ ràng, với đích đến (`to:`) chính là IP thật của Pod Nginx!

---

## 🕵️‍♂️ Thí nghiệm 3: Xem trạng thái bằng Conntrack

Khi iptables thực hiện DNAT, nó lưu lại "nhật ký" ở trong module `conntrack` để khi gói tin quay về, nó biết đường dịch ngược lại (từ IP Thật -> IP Ảo).

**Trên Terminal đang SSH vào `controlplane`:**

1. Gọi lệnh curl vào ClusterIP từ `pod-a` (Pod chúng ta đã tạo ở Tập 2):
   ```bash
   kubectl exec pod-a -- curl -s http://10.96.123.45 > /dev/null
   ```

**Ngay lập tức, chuyển sang Terminal đang SSH vào `worker1` (nơi đang chạy pod-a):**

2. Cài đặt công cụ `conntrack` nếu chưa được cài đặt (trên Ubuntu cloud-init mặc định có thể chưa có sẵn CLI này):
   ```bash
   sudo apt-get update && sudo apt-get install -y conntrack
   ```

3. Xem bản ghi conntrack của IP VIP này — chạy trong vòng vài giây sau lệnh curl, vì entry chỉ tồn tại tạm thời:
   ```bash
   sudo conntrack -L | grep 10.96.123.45
   ```

   *Nhận xét:* Bạn sẽ thấy một bản ghi kết nối (ở trạng thái `ESTABLISHED` hoặc `TIME_WAIT` nếu đã đóng), trông tương tự như thế này:
   ```text
   tcp      6 118 TIME_WAIT src=10.244.1.7 dst=10.96.123.45 sport=35350 dport=80 src=10.244.1.6 dst=10.244.1.7 sport=80 dport=35350 [ASSURED] mark=0 use=1
   ```

   > **🔍 Mổ xẻ chi tiết bản ghi Conntrack:**
   > * **`tcp 6`**: Giao thức TCP (mã protocol là 6).
   > * **`118 TIME_WAIT`**: Trạng thái kết nối TCP (đang ở bước đóng kết nối một cách an toàn) và số giây TTL còn lại trước khi bản ghi bị xóa khỏi cache.
   > * **Chiều đi (Original tuple)**: `src=10.244.1.7 dst=10.96.123.45 sport=35350 dport=80`
   >   - Gói tin xuất phát từ `pod-a` (`src=10.244.1.7`) đi tới ClusterIP ảo (`dst=10.96.123.45`) cổng `80`.
   > * **Chiều về (Reply tuple)**: `src=10.244.1.6 dst=10.244.1.7 sport=80 dport=35350`
   >   - **Đây chính là bí mật:** Gói tin phản hồi thực tế được gửi về từ **IP thật của Pod Nginx** (`src=10.244.1.6`), chứ không phải ClusterIP!
   >   - Khi gói tin đi qua Node, `iptables` đã thực hiện **DNAT** đổi IP đích ảo thành IP thật của Pod. `conntrack` ghi nhớ điều này để khi gói tin quay về từ Pod thật (`src=10.244.1.6`), kernel sẽ **tự động dịch ngược lại** (SNAT) thành ClusterIP để Client (`pod-a`) không phát giác ra sự thay đổi.
   > * **`[ASSURED]`**: Đánh dấu kết nối đã truyền nhận thành công hai chiều và không bị tự động xóa khi bảng NAT cache đầy.

---

## 🌐 Thí nghiệm 4: NodePort mở cửa ra thế giới

**Trên Terminal đang SSH vào `controlplane`:**

1. Chuyển Service từ kiểu `ClusterIP` thành `NodePort`:
   ```bash
   kubectl patch svc nginx -p '{"spec": {"type": "NodePort"}}'
   kubectl get svc nginx
   ```
   *Kết quả:* Ở cột PORT(S), bạn sẽ thấy nó cấp thêm 1 port ngẫu nhiên trong dải 30000-32767 (ví dụ: `80:31234/TCP`).

**Đứng tại Terminal máy Host (macOS/Windows của bạn):**

2. Lấy IP tĩnh của 2 worker:
   ```bash
   multipass info worker1 | grep IPv4
   multipass info worker2 | grep IPv4
   ```

3. Thử gọi `curl` vào Port 31234 bằng IP của MỌI NODE:
   ```bash
   curl http://<IP_WORKER_1>:31234
   curl http://<IP_WORKER_2>:31234
   curl http://<IP_CONTROLPLANE>:31234
   ```
   *Kết quả:* Ngạc nhiên chưa? Kể cả bạn gọi vào Node không chứa Pod nginx nào, nó vẫn trả về thành công! Đó là vì `kube-proxy` đã mở cái Port 31234 trên **TẤT CẢ CÁC NODE**, và mọi gói tin đập vào Port đó đều sẽ bị iptables dịch chuyển (DNAT) ném sang đúng cái Node đang chứa Pod.

---

## ✅ Tổng kết
Bạn đã vừa thấu hiểu một trong những kiến trúc kinh điển nhất của K8s:
1. Virtual IP hoàn toàn không có card mạng, chỉ là ảo ảnh do `iptables DNAT` tạo ra.
2. Load Balancing trong `kube-proxy` (chế độ iptables) thực chất là dùng xác suất thống kê `statistic mode random`.
3. NodePort rải rác trên toàn bộ các node, giúp traffic vào từ mọi ngóc ngách đều trôi được đến Pod.
