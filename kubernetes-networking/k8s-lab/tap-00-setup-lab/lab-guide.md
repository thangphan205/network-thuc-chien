# Lab Module 0: Xây dựng cụm Kubernetes 3 Nodes (Kubeadm + Multipass)

Để quan sát được bản chất cách Kubernetes thao tác với Linux Networking, chúng ta cần một cụm K8s thực thụ (thay vì Minikube hay Docker Desktop). Bài lab này hướng dẫn bạn dựng một cụm K8s 3 node siêu nhanh bằng **Multipass** và **Kubeadm**. Giải pháp này đặc biệt tối ưu và hỗ trợ tốt cho macOS sử dụng chip Apple Silicon (M1/M2/M3) và cả chip Intel.

## 🛠 Yêu cầu hệ thống
1. Máy tính macOS.
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

## 🔬 Bước 3: Quan sát trạng thái "Không có CNI"

Trở lại shell của `controlplane`, trước khi cài CNI, hãy quan sát điều gì xảy ra — đây là **thí nghiệm đầu tiên** của khóa học.

```bash
kubectl get nodes
```

Kết quả mong đợi:
```
NAME           STATUS     ROLES           AGE
controlplane   NotReady   control-plane   1m  # ← NotReady!
```

```bash
kubectl get pods -n kube-system
```

Kết quả mong đợi:
```
NAME                    READY   STATUS    RESTARTS
coredns-xxx             0/1     Pending   0        # ← Pending!
```

> **Tại sao?** Thiếu CNI = không có mạng = Node `NotReady` = CoreDNS `Pending`. Kubernetes không thể cấp phát IP hay kết nối các Pod khi chưa có CNI Plugin.

---

## 🚀 Bước 4: Cài đặt CNI Plugin (Flannel)

Bây giờ hãy "chữa bệnh" cho cluster bằng cách cài CNI:

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

Theo dõi cluster chuyển sang `Ready`:
```bash
kubectl get nodes -w
```

---

## 🚀 Bước 5: Đưa các Worker Nodes vào Cụm
Mở terminal mới trên máy tính host của bạn.

**Trên Worker 1:**
```bash
multipass exec worker1 -- sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

**Trên Worker 2:**
```bash
multipass exec worker2 -- sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```
*Lưu ý: Bạn dán nguyên lệnh join đã copy ở Bước 2 thay thế vào phía trên.*

---

## ✅ Bước 6: Kiểm tra cụm thành công
Quay trở lại terminal đang SSH vào `controlplane`, chạy lệnh kiểm tra các Nodes:

```bash
kubectl get nodes -o wide
```
*Kết quả mong đợi:* Cả 3 nodes (controlplane, worker1, worker2) đều ở trạng thái **Ready**. (Trạng thái Ready chứng tỏ CNI Flannel đã khởi động thành công và mạng giữa các node đã thông).

**Chúc mừng!** Bạn đã sở hữu một cụm Kubernetes thực thụ với toàn quyền truy cập ở mức OS. Bạn có thể giữ cụm này để thực hiện Lab Module 1 và các module tiếp theo.

---

## 🧹 Quản lý vòng đời Lab
- **Tạm dừng lab (Tắt VMs để giải phóng RAM):** Chạy lệnh `multipass stop controlplane worker1 worker2`.
- **Bật lại lab:** Chạy lệnh `multipass start controlplane worker1 worker2`.
- **Xóa toàn bộ lab (Làm lại từ đầu):** Chạy script dọn dẹp `./reset-lab.sh`.