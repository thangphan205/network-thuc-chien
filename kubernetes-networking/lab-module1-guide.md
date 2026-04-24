# Lab Module 1: Mô hình Mạng Kubernetes & Nguyên lý cốt lõi

Bài lab này giúp sinh viên thực hành và kiểm chứng 3 khái niệm cốt lõi của mạng Kubernetes:
1. **Mô hình IP-per-Pod (Flat Network):** Các Pod có thể giao tiếp trực tiếp với nhau mà không cần NAT.
2. **Pause Container & Shared Network Namespace:** Các container trong cùng một Pod chia sẻ chung không gian mạng (IP, Port, Routing).
3. **CNI & Veth Pair:** Cách thức Kubelet và CNI plugin cấp phát mạng cho Pod.

---

## 🛠 Chuẩn bị Môi trường

Sử dụng file cấu hình `lab-module1.yml` để tạo các Pod phục vụ bài lab:
```bash
kubectl apply -f lab-module1.yml
```
Kiểm tra trạng thái các Pod, đợi đến khi tất cả đều ở trạng thái `Running`:
```bash
kubectl get pods -o wide
```

---

## 🧪 Phần 1: Kiểm chứng Mô hình "IP-per-Pod"
Mỗi Pod trong K8s được cấp phát một địa chỉ IP duy nhất trên toàn cụm.

**Bước 1: Xem IP của các Pod**
```bash
kubectl get pods -o wide
```
*Hành động:* Ghi chú lại IP của `pod-a` (chạy Nginx) và `pod-b` (chạy Netshoot - một image chứa đầy đủ các công cụ mạng).

**Bước 2: Ping từ Pod này sang Pod kia**
Sử dụng `pod-b` để ping tới địa chỉ IP của `pod-a`:
```bash
# Thay <IP_POD_A> bằng IP thực tế của pod-a
kubectl exec -it pod-b -- ping -c 3 <IP_POD_A>
```
*Kết quả mong đợi:* Nhận được response bình thường. Mặc dù 2 Pod có thể khác Node, chúng vẫn ping được trực tiếp.

**Bước 3: Gửi HTTP Request**
Gọi cURL từ `pod-b` sang `pod-a`:
```bash
kubectl exec -it pod-b -- curl -s http://<IP_POD_A> | grep title
```
*Kết quả mong đợi:* Trả về HTML chứa dòng chữ "Welcome to nginx!".

---

## 🧪 Phần 2: Pause Container & Network Namespaces
Các container trong cùng một Pod được bọc chung trong một Network Namespace (được tạo và giữ bởi `pause` container). Chúng sẽ chung địa chỉ IP và chung interface.

**Bước 1: Lấy IP của Pod chứa nhiều container**
```bash
kubectl get pod pod-shared-net -o wide
```
*Giải thích:* Pod `pod-shared-net` chứa 2 container (`web` và `netshoot`). Cả 2 sẽ dùng chung một IP hiển thị tại lệnh này.

**Bước 2: Kết nối localhost từ container này sang container khác**
Vào container `netshoot` và cURL tới `localhost` để truy cập Nginx đang chạy trên container `web` (ở cổng 80):
```bash
kubectl exec -it pod-shared-net -c netshoot -- curl -s http://localhost | grep title
```
*Kết quả mong đợi:* Lệnh cURL thành công. Điều này chứng minh các container trong Pod dùng chung một `lo` (loopback) interface.

**Bước 3: Xem các Network Interfaces bên trong Pod**
Vẫn tại container `netshoot`, kiểm tra các network interfaces:
```bash
kubectl exec -it pod-shared-net -c netshoot -- ip addr
```
*Kết quả mong đợi:* Bạn sẽ chỉ thấy 2 interface: `lo` (loopback) và `eth0` (virtual ethernet interface ảo được CNI gắn vào Pod để ra ngoài).

---

## 🧪 Phần 3: Khám phá CNI và Veth Pair (Nâng cao)
Khi tạo Pod, Kubelet sẽ gọi CNI Plugin để xin IP và thiết lập một cặp cáp mạng ảo (veth pair) kết nối từ Node vào Pod.

**Bước 1: Xác định interface bên trong Pod**
```bash
kubectl exec -it pod-a -- ip link show eth0
```
*Kết quả:* Bạn sẽ thấy output có dạng `eth0@if<X>`. Số `X` (ví dụ: `if15`) là index của veth interface ở phía ngoài Node.

**Bước 2: Xác định Node đang chạy Pod**
```bash
kubectl get pod pod-a -o wide
```
*Hành động:* Xem Pod đang chạy trên Node nào (ví dụ: `worker-1`) và thực hiện SSH/truy cập vào Node đó.

**Bước 3: Khám phá Veth Pair trên Node**
Đứng trên Node chạy `pod-a`, tìm interface có index bằng `<X>` vừa tìm được ở Bước 1:
```bash
ip link | grep -A 1 "^<X>:"
```
*Kết quả mong đợi:* Hiển thị một interface tên dạng `veth...` hoặc `cali...`. Đây chính là đầu cáp mạng ảo còn lại được cắm trên Node, nối thẳng vào `eth0` của Pod.

**Bước 4: Xem file cấu hình của CNI**
Vẫn đứng trên Node, khám phá thư mục chứa file cấu hình của CNI:
```bash
ls -l /etc/cni/net.d/
cat /etc/cni/net.d/*.conflist
```
*Giải thích:* Đây là nơi Kubelet tìm đến để biết phải gọi plugin CNI nào (ví dụ: Calico, Flannel) để cài đặt mạng cho các Pod trên Node.

---

## 🧹 Dọn dẹp môi trường
Hoàn thành lab, dọn dẹp các resources đã tạo:
```bash
kubectl delete -f lab-module1.yml
```
