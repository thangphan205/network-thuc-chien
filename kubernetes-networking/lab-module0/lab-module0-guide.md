# Lab Module 0: Xây dựng cụm Kubernetes 3 Nodes (Kubeadm + Vagrant)

Để quan sát được bản chất cách Kubernetes thao tác với Linux Networking, chúng ta cần một cụm K8s thực thụ (thay vì Minikube hay Docker Desktop). Bài lab này hướng dẫn bạn dựng một cụm K8s 3 node siêu nhanh bằng **Vagrant** và **Kubeadm**.

## 🛠 Yêu cầu hệ thống
1. Đã cài đặt **VirtualBox**.
2. Đã cài đặt **Vagrant**.
3. Máy tính host (máy tính của bạn) cần tối thiểu 8GB RAM (6GB sẽ được cấp cho 3 VMs).

---

## 🚀 Bước 1: Khởi động 3 Máy ảo (VMs)
Mở terminal, di chuyển vào thư mục `lab-module0` (nơi chứa file `Vagrantfile`) và chạy lệnh:

```bash
vagrant up
```
*Lưu ý: Quá trình này mất khoảng 5-10 phút. Vagrant sẽ tải image Ubuntu, tạo 3 máy ảo (`controlplane`, `worker1`, `worker2`), và tự động cài đặt sẵn Containerd, Kubelet, Kubeadm, Kubectl ở bên trong.*

Kiểm tra trạng thái các máy ảo:
```bash
vagrant status
```

---

## 🚀 Bước 2: Khởi tạo Control Plane
Chỉ thực hiện trên node `controlplane`.

1. SSH vào node controlplane:
   ```bash
   vagrant ssh controlplane
   ```
2. Khởi tạo cụm Kubernetes với `kubeadm` (sử dụng IP của interface ảo `192.168.56.10` và dải IP cho Pod là `10.244.0.0/16`):
   ```bash
   sudo kubeadm init --apiserver-advertise-address=192.168.56.10 --pod-network-cidr=10.244.0.0/16
   ```
3. Copy file cấu hình `kubeconfig` để có quyền dùng `kubectl`:
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```
4. **Cài đặt CNI Plugin (Flannel):** Vì đây là Lab về mạng, chúng ta cài Flannel (CNI đơn giản nhất) để cấp phát IP cho các Pod.
   ```bash
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```
5. **(Quan trọng) Lấy lệnh Join:** Cuộn lên phần output của lệnh `kubeadm init`, copy lại lệnh bắt đầu bằng `kubeadm join ...` (có chứa token và hash).

---

## 🚀 Bước 3: Đưa các Worker Nodes vào Cụm
Mở 2 tab terminal mới trên máy tính của bạn để SSH vào `worker1` và `worker2`.

**Trên Worker 1:**
```bash
vagrant ssh worker1
# Paste lệnh kubeadm join mà bạn vừa copy ở Bước 2. Cần chạy dưới quyền sudo.
# Ví dụ: sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

**Trên Worker 2:**
```bash
vagrant ssh worker2
# Tương tự như worker 1, dán lệnh kubeadm join chạy với sudo.
```

---

## ✅ Bước 4: Kiểm tra cụm thành công
Quay trở lại terminal đang SSH vào `controlplane`, chạy lệnh kiểm tra các Nodes:

```bash
kubectl get nodes -o wide
```
*Kết quả mong đợi:* Cả 3 nodes (controlplane, worker1, worker2) đều ở trạng thái **Ready**. (Trạng thái Ready chứng tỏ CNI Flannel đã khởi động thành công và mạng giữa các node đã thông).

**Chúc mừng!** Bạn đã sở hữu một cụm Kubernetes thực thụ với toàn quyền truy cập ở mức OS. Bạn có thể giữ cụm này để thực hiện Lab Module 1 và các module tiếp theo.

---

## 🧹 Quản lý vòng đời Lab
- **Tạm dừng lab (Tắt VMs để giải phóng RAM):** Đứng ở thư mục `lab-module0`, chạy lệnh `vagrant halt`.
- **Bật lại lab:** Chạy lệnh `vagrant up`.
- **Xóa toàn bộ lab (Làm lại từ đầu):** Chạy lệnh `vagrant destroy -f`.
