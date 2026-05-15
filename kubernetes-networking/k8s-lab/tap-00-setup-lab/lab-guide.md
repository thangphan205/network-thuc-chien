# Lab Module 0: Xây dựng cụm Kubernetes 3 Nodes (Kubeadm + Multipass)

Để quan sát được bản chất cách Kubernetes thao tác với Linux Networking, chúng ta cần một cụm K8s thực thụ (thay vì Minikube hay Docker Desktop). Bài lab này hướng dẫn bạn dựng một cụm K8s 3 node siêu nhanh bằng **Multipass** và **Kubeadm**. Giải pháp này đặc biệt tối ưu và hỗ trợ tốt cho macOS sử dụng chip Apple Silicon (M1/M2/M3) và cả chip Intel.

## 🛠 Yêu cầu hệ thống
1. Máy tính macOS hoặc Windows 10+.
2. Máy tính host cần tối thiểu 8GB RAM (khoảng 5GB sẽ được cấp cho 3 VMs).
3. (Tùy chọn) Đã cài đặt sẵn **Multipass**. Nếu chưa có, script sẽ tự động cài đặt.

---

## 🚀 Bước 1: Khởi động 3 Máy ảo (VMs)
Mở terminal, di chuyển vào thư mục `tap-00-setup-lab` và chạy kịch bản tự động hóa:

```bash
./setup-lab.sh
```
*Lưu ý: Quá trình này mất khoảng 5-10 phút. Script sẽ tạo 3 máy ảo (`controlplane`, `worker1`, `worker2`), và tự động chạy cloud-init để cài đặt sẵn Containerd, Kubelet, Kubeadm, Kubectl ở bên trong.*

Kiểm tra lại trạng thái các máy ảo bằng lệnh:
```bash
multipass list
```

---

## 🚀 Bước 2: Khởi tạo Control Plane
Chỉ thực hiện trên node `controlplane`.

1. Shell vào node controlplane:
   ```bash
   multipass shell controlplane
   ```
2. Lấy IP của `controlplane` (nó là IPv4 ứng với interface mạng chính):
   ```bash
   ip a
   ```
   *Giả sử IP của bạn là `192.168.105.2`*
3. Khởi tạo cụm Kubernetes với `kubeadm` (sử dụng IP vừa tìm được và dải IP cho Pod là `10.244.0.0/16`):
   ```bash
   sudo kubeadm init --apiserver-advertise-address=<IP_CỦA_CONTROLPLANE> --pod-network-cidr=10.244.0.0/16
   ```
4. Copy file cấu hình `kubeconfig` để có quyền dùng `kubectl`:
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```
5. **(Quan trọng) Lấy lệnh Join:** Cuộn lên phần output của lệnh `kubeadm init`, copy lại lệnh bắt đầu bằng `kubeadm join ...` (có chứa token và hash). Thoát khỏi shell bằng lệnh `exit`.

---

## 🚀 Bước 3: Đưa các Worker Nodes vào Cụm

**Trên Worker 1:**
Mở terminal mới, truy cập vào `worker1`:
```bash
multipass shell worker1

# Sau đó chạy lệnh join:
sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```
*(Chạy xong có thể gõ `exit` để thoát)*

**Trên Worker 2:**
Truy cập vào `worker2`:
```bash
multipass shell worker2

# Sau đó chạy lệnh join:
sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```
*(Chạy xong có thể gõ `exit` để thoát)*

*Lưu ý: Bạn dán nguyên lệnh join đã copy ở Bước 2 thay thế vào lệnh bên trên.*

---

## ✅ Bước 4: Kiểm tra cụm và gán nhãn (Label)
Quay trở lại terminal đang SSH vào `controlplane`, chạy lệnh kiểm tra các Nodes:

```bash
kubectl get nodes
```
*Kết quả mong đợi:* Cả 3 nodes (controlplane, worker1, worker2) đều xuất hiện nhưng ở trạng thái **NotReady**. Mặc định, 2 node worker sẽ có ROLES là `<none>`.

*(Tùy chọn)* Để danh sách Node hiển thị đẹp và chuyên nghiệp hơn, bạn có thể gán nhãn (Role) cho 2 worker bằng lệnh sau:
```bash
kubectl label node worker1 node-role.kubernetes.io/worker=
kubectl label node worker2 node-role.kubernetes.io/worker=
```
Chạy lại `kubectl get nodes`, bạn sẽ thấy cột ROLES hiện chữ `worker` rất đẹp mắt!

> **Đừng lo lắng!** Việc các Node ở trạng thái `NotReady` là hoàn toàn bình thường vì cụm của chúng ta chưa được cài đặt mạng (CNI). 
> 👉 Hãy chuyển sang bài **Lab Tập 1 (tap-01)** để tìm hiểu lý do tại sao Kubernetes lại cần CNI và cách "chữa bệnh" cho cụm nhé!
---

## 🧹 Quản lý vòng đời Lab
- **Tạm dừng lab (Tắt VMs để giải phóng RAM):** Chạy lệnh `multipass stop controlplane worker1 worker2`.
- **Bật lại lab:** Chạy lệnh `multipass start controlplane worker1 worker2`.
- **Xóa toàn bộ lab (Làm lại từ đầu):** Chạy script dọn dẹp `./reset-lab.sh`.