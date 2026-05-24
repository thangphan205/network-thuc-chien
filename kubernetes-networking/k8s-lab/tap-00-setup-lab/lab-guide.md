# Lab Module 0: Xây dựng cụm Kubernetes 3 Nodes (Kubeadm + Multipass)

Để quan sát được bản chất cách Kubernetes thao tác với Linux Networking, chúng ta cần một cụm K8s thực thụ (thay vì Minikube hay Docker Desktop). Bài lab này hướng dẫn bạn dựng một cụm K8s 3 node siêu nhanh bằng **Multipass** và **Kubeadm**. 

Đặc biệt, hệ thống lab đã được tối ưu hóa sâu để hỗ trợ **song song và độc lập** cả hai dòng chip phổ biến nhất hiện nay:
*   **ARM**: Apple Silicon M1/M2/M3/M4 trên macOS.
*   **AMD / Intel**: Bộ vi xử lý cấu trúc x86_64 trên Windows, Linux và macOS đời cũ.

---

## 💻 Sự khác biệt về Kiến trúc: ARM vs AMD (x86_64)

Khi chạy ảo hóa mạng và Kubernetes cục bộ, việc nhận diện đúng kiến trúc chip giúp tối ưu hóa hiệu năng cực kỳ đáng kể:

| Đặc tính | Chip ARM (Apple Silicon M1/M2/M3/M4) | Chip AMD / Intel (x86_64) |
| :--- | :--- | :--- |
| **Công nghệ ảo hóa** | Native ARM-on-ARM Virtualization | Native x86-on-x86 Virtualization |
| **Driver Multipass tốt nhất** | `qemu` hoặc `virtualization` (Apple framework) | `hyper-v` (Windows) · `kvm` (Linux) · `qemu` |
| **Hệ điều hành máy ảo** | Ubuntu 26.04 LTS **ARM64** | Ubuntu 26.04 LTS **AMD64** |
| **Docker Images chạy trong K8s** | Ưu tiên các Image hỗ trợ Multi-Arch hoặc ARM64 | Chạy các Image kiến trúc AMD64 chuẩn |
| **Lỗi phổ biến nếu chạy sai** | Lỗi hiệu năng do dịch lệnh (Emulation) hoặc crash | Không thể chạy được VM nếu bật ảo hóa sai driver |

---

## 🛠 Yêu cầu hệ thống

1. **Hệ điều hành**: macOS 13+ hoặc Windows 10/11 Pro/Enterprise (yêu cầu bật Hyper-V).
2. **Tài nguyên**: Máy tính host cần tối thiểu **8GB RAM** (khoảng 5GB sẽ cấp cho 3 VMs) và **4 CPU Cores**. Khuyên dùng **16GB RAM** để cụm chạy mượt mà nhất.
3. **Cài đặt sẵn Multipass**: Nếu chưa cài, script tự động cài qua Homebrew (trên macOS) hoặc Snap (trên Linux).

---

## 🚀 Bước 1: Khởi động 3 Máy ảo (VMs) phù hợp với Chip của bạn

Hệ thống cung cấp cho bạn 2 cách chạy cực kỳ linh hoạt:

### Cách 1: Sử dụng Router tự động (Khuyên dùng)
Bạn chỉ cần mở terminal tại thư mục `tap-00-setup-lab` và chạy script mặc định. Script này sẽ tự động phát hiện kiến trúc chip của bạn để gọi đúng tệp tối ưu:
```bash
./setup-lab.sh
```

### Cách 2: Chạy trực tiếp script chuyên biệt cho chip của bạn

*   **Nếu bạn dùng máy Mac sử dụng chip Apple Silicon (M1/M2/M3/M4 - ARM):**
    ```bash
    ./setup-lab-arm.sh
    ```
*   **Nếu bạn dùng máy tính Windows, Linux hoặc Mac chạy chip Intel/AMD (x86_64):**
    ```bash
    ./setup-lab-amd.sh
    ```

> ⏳ **Quá trình này mất khoảng 3 - 5 phút.** Script sẽ tạo 3 máy ảo (`controlplane`, `worker1`, `worker2`), và tự động chạy cơ chế `cloud-init` để cấu hình Containerd, Kubeadm, Kubelet và Kubectl ở bên trong.

Kiểm tra trạng thái các máy ảo sau khi hoàn tất:
```bash
multipass list
```

---

## 🚀 Bước 2: Khởi tạo Control Plane

Lưu ý: Chỉ thực hiện các câu lệnh này bên trong máy ảo `controlplane`.

1. **Shell vào node controlplane:**
   ```bash
   multipass shell controlplane
   ```
2. **Lấy IP của controlplane:**
   ```bash
   ip a
   ```
   *Nhìn vào interface mạng chính (thường là `enp0s2` hoặc `eth0`), ví dụ IP của bạn là `192.168.64.10`.*

3. **Khởi tạo cụm Kubernetes bằng Kubeadm:**
   Sử dụng IP vừa lấy được ở trên và dải IP dành cho mạng Pod là `10.244.0.0/16`:
   ```bash
   sudo kubeadm init --apiserver-advertise-address=<IP_CỦA_CONTROLPLANE> --pod-network-cidr=10.244.0.0/16
   ```

4. **Cấu hình quyền Kubectl cho user hiện tại:**
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

5. **Lấy lệnh Join:**
   Hãy nhìn vào output cuối cùng của lệnh `kubeadm init`, sao chép lại toàn bộ dòng lệnh `kubeadm join <IP>:6443 --token ...` để sử dụng ở bước sau.
   Sau đó gõ `exit` để thoát khỏi máy ảo `controlplane`.

---

## 🚀 Bước 3: Đưa các Worker Nodes vào Cụm

### Thực hiện trên Worker 1:
```bash
multipass shell worker1
```
Dán câu lệnh join bạn vừa copy ở Bước 2 (thêm `sudo` ở đầu):
```bash
sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```
Gõ `exit` để thoát.

### Thực hiện trên Worker 2:
```bash
multipass shell worker2
```
Dán câu lệnh tương tự:
```bash
sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```
Gõ `exit` để thoát.

---

## ✅ Bước 4: Kiểm tra Cụm & Nhận diện Kiến trúc Chip

Quay trở lại terminal chính hoặc SSH lại vào `controlplane` (`multipass shell controlplane`), kiểm tra xem các Node đã kết nối thành công chưa:

```bash
kubectl get nodes -o wide
```

### Cách xác thực kiến trúc CPU của cụm:
Hãy chú ý cột **ARCHITECTURE** trong kết quả trả về của lệnh trên:
*   Nếu bạn chạy trên Mac M1/M2/M3: Kiến trúc hiển thị sẽ là **arm64**.
*   Nếu bạn chạy trên Windows/Intel/AMD: Kiến trúc hiển thị sẽ là **amd64**.

*Lưu ý: Lúc này các node sẽ ở trạng thái **NotReady**. Đây là hiện tượng bình thường do cụm chưa có CNI (Container Network Interface). Hãy sang tập tiếp theo để bắt đầu hành trình cài đặt mạng cho Pod!*

### Gán nhãn Role cho Worker Nodes hiển thị trực quan:
```bash
kubectl label node worker1 node-role.kubernetes.io/worker=
kubectl label node worker2 node-role.kubernetes.io/worker=
```

---

## ⚠️ Lưu ý Quan trọng khi Deploy Ứng dụng trên Chip ARM (Apple Silicon)

Nếu bạn chạy lab trên chip ARM, khi deploy các ứng dụng tự xây dựng hoặc bên thứ ba, hãy đảm bảo:
1. **Sử dụng Multi-Arch Images**: Hầu hết các ứng dụng phổ biến như Nginx, Alpine, Ubuntu, Redis... đều đã hỗ trợ multi-arch. Docker/Kubernetes sẽ tự tải bản `arm64` về chạy.
2. **Tránh lỗi `Exec format error`**: Lỗi này xảy ra khi bạn cố tình chạy một container image chỉ được build cho kiến trúc `amd64` (x86_64) trên máy ảo `arm64`. Nếu tự build docker image, hãy build bằng công cụ hỗ trợ multi-arch như `docker buildx` hoặc build trực tiếp trên máy Mac M-series của bạn.

---

## 🧹 Quản lý vòng đời Lab

*   **Tạm dừng cụm lab (Giải phóng RAM máy host)**:
    ```bash
    multipass stop controlplane worker1 worker2
    ```
*   **Bật lại cụm lab**:
    ```bash
    multipass start controlplane worker1 worker2
    ```
*   **Xóa sạch hoàn toàn làm lại từ đầu**:
    ```bash
    ./reset-lab.sh
    ```