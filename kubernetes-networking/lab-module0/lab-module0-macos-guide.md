# Lab Module 0: Xây dựng K8s Cluster trên macOS (Multipass)

Nếu bạn đang sử dụng **macOS** (đặc biệt là các dòng máy Mac sử dụng chip **Apple Silicon M1/M2/M3/M4**), **VirtualBox sẽ không hoạt động**. Thay vì dùng Vagrant + VirtualBox, giải pháp thay thế tối ưu, native và nhẹ nhàng nhất cho macOS là sử dụng **Multipass** (của Canonical - cha đẻ Ubuntu).

Bài lab này sẽ hướng dẫn bạn tạo cụm 3 VMs tương đương như Vagrant nhưng bằng Multipass.

## 🛠 Yêu cầu hệ thống
1. Máy Mac (Intel hoặc Apple Silicon) với ít nhất 8GB RAM.
2. Cài đặt sẵn **Homebrew** (nếu chưa cài, truy cập `brew.sh`).

---

## 🚀 Bước 1: Khởi động 3 Máy ảo với Script
Chúng ta có 1 script `setup-macos-multipass.sh` kết hợp với `k8s-cloud-init.yaml` để tạo tự động 3 máy ảo Ubuntu và cài sẵn Kubeadm.

Mở terminal, di chuyển vào thư mục `lab-module0` và chạy:
```bash
chmod +x setup-macos-multipass.sh
./setup-macos-multipass.sh
```
*Lưu ý: Chờ khoảng 3-5 phút để Multipass tải Image Ubuntu về, tạo 3 VM (controlplane, worker1, worker2) và ngầm chạy Cloud-Init để cài đặt Containerd, Kubeadm, Kubectl.*

Sau khi xong, hãy kiểm tra các VM đã chạy hay chưa bằng lệnh:
```bash
multipass list
```

---

## 🚀 Bước 2: Khởi tạo Control Plane
Chỉ thực hiện trên node `controlplane`.

1. Vào shell của Control Plane:
   ```bash
   multipass shell controlplane
   ```
2. Khởi tạo K8s Cluster (Kubeadm sẽ tự lấy IP mặc định của VM):
   ```bash
   sudo kubeadm init --pod-network-cidr=10.244.0.0/16
   ```
3. Copy file cấu hình `kubeconfig` để dùng `kubectl`:
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```
4. **Copy lại lệnh `kubeadm join`** ở cuối output của `kubeadm init` (có chứa token).

---

## 🔬 Bước 3: Quan sát trạng thái "Không có CNI"

Trước khi cài CNI, hãy quan sát điều gì xảy ra — đây là **thí nghiệm đầu tiên** của khóa học.

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
Mở thêm tab terminal trên macOS của bạn để truy cập vào từng Worker node.

**Trên Worker 1:**
```bash
multipass shell worker1
# Chạy lệnh kubeadm join bằng quyền sudo (Dán lệnh bạn copy ở bước 2)
# Ví dụ: sudo kubeadm join 192.168.64.2:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

**Trên Worker 2:**
```bash
multipass shell worker2
# Chạy lệnh kubeadm join tương tự worker 1
```

---

## ✅ Bước 6: Kiểm tra cụm thành công
Quay trở lại terminal đang ở `controlplane` (hoặc mở lại bằng `multipass shell controlplane`), chạy lệnh kiểm tra:

```bash
kubectl get nodes -o wide
```
*Kết quả:* Tất cả 3 nodes chuyển trạng thái `Ready` là thành công! Bạn đã sẵn sàng thực hành Lab Module 1.

---

## 🧹 Quản lý vòng đời Lab với Multipass
- **Tạm dừng máy ảo (tiết kiệm pin/RAM):**
  ```bash
  multipass stop controlplane worker1 worker2
  ```
- **Bật lại máy ảo:**
  ```bash
  multipass start controlplane worker1 worker2
  ```
- **Xóa toàn bộ Lab (Xóa không phục hồi):**
  ```bash
  multipass delete controlplane worker1 worker2
  multipass purge
  ```
