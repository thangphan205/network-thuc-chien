# Hướng Dẫn Setup K8s Lab Local (Tập 00)

Chào mừng bạn đến với môi trường thực hành Kubernetes Networking! Lab này được thiết kế tối ưu hóa để chạy trực tiếp trên máy tính cá nhân của bạn (macOS hoặc Windows) sử dụng **Multipass**. Bạn sẽ có một cụm Kubernetes thực thụ với 3 nodes (1 Master, 2 Worker) để thoải mái thực hành qua toàn bộ 45 tập của khoá học.

---

## 💻 1. Yêu cầu hệ thống & Chuẩn bị

Để lab chạy mượt mà, máy tính của bạn cần đáp ứng:
- **CPU:** Tối thiểu 4 cores (khuyến nghị 8 cores).
- **RAM:** Tối thiểu 8 GB (khuyến nghị 16 GB).
- **Ổ cứng:** Trống ít nhất 60 GB.
- **Hệ điều hành:** macOS (có hỗ trợ M-series rất tốt) hoặc Windows 10/11 (qua Hyper-V).

**Công cụ cần cài đặt:**
Bạn chỉ cần cài đặt **Multipass** (công cụ ảo hóa siêu nhẹ của Canonical - công ty mẹ của Ubuntu).

*Dành cho macOS (sử dụng Homebrew):*
```bash
brew install multipass
```
*(Trên Windows, bạn có thể tải file cài đặt từ trang chủ [Multipass](https://multipass.run/).)*

Hãy kiểm tra xem Multipass đã cài đặt thành công chưa:
```bash
multipass version
```

---

## 🚀 2. Dựng Cluster (Chỉ với 1 lệnh)

Tất cả sự phức tạp (tạo VM, cài Docker/Containerd, chạy Kubeadm) đã được đóng gói tự động trong script `setup-lab.sh`. 

Mở terminal và trỏ vào thư mục lab:
```bash
cd tap-00-setup-lab/
```

Bạn có 2 lựa chọn để dựng cluster:

**Lựa chọn A: Dựng cluster "sạch" (Không có mạng/CNI)** - Khuyên dùng để thực hành step-by-step:
```bash
./setup-lab.sh
```

**Lựa chọn B: Dựng cluster và tự cài sẵn CNI (Dành cho các tập cụ thể):**
```bash
./setup-lab.sh flannel   # Dùng khi học Tập 6-10
./setup-lab.sh calico    # Dùng khi học Tập 11-26
./setup-lab.sh cilium    # Dùng khi học Tập 27-43
```

> ⏳ **Quá trình này mất khoảng 3 - 5 phút**. Multipass sẽ tải image Ubuntu 26.04 (lần đầu tiên có thể hơi lâu một chút), tạo 3 máy ảo, tự động cài K8s và join các worker node lại với nhau.

---

## 🔌 3. Kết nối từ máy tính của bạn

Sau khi script hoàn tất, nó sẽ tự động copy file `kubeconfig` ra máy host của bạn (lưu ở `~/.kube/k8s-lab-config`).

Để sử dụng `kubectl` quản trị cụm từ máy tính của bạn, hãy trỏ biến môi trường:
```bash
export KUBECONFIG=~/.kube/k8s-lab-config
```
*(Mẹo: Bạn có thể đưa lệnh này vào cuối file `~/.zshrc` hoặc `~/.bashrc` để không phải gõ lại mỗi lần mở tab terminal mới).*

Bây giờ, hãy thử kiểm tra các node:
```bash
kubectl get nodes -o wide
```
**Lưu ý:** Nếu bạn dùng **Lựa chọn A**, các node sẽ ở trạng thái `NotReady`. Đừng lo lắng! Lý do là vì K8s chưa có plugin mạng (CNI). Sau khi bạn cài đặt CNI ở bước tiếp theo, chúng sẽ tự động chuyển sang `Ready`.

---

## 🌐 4. Cài đặt CNI (Tùy tập học)

Tùy vào tập lab bạn đang làm mà áp dụng lệnh cài CNI tương ứng:

**Flannel (Tập 6-10):**
```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Calico (Tập 11-26):**
```bash
curl -s https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml | sed "s|192.168.0.0/16|10.244.0.0/16|g" | kubectl apply -f -
```

**Cilium (Tập 27-43):**
*(Yêu cầu đã cài đặt `helm` trên máy tính của bạn)*
```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true
```

Hãy đợi khoảng 1-2 phút cho các Pod hệ thống chạy lên và kiểm tra lại trạng thái:
```bash
kubectl get nodes
```
Tất cả các node chuyển sang `Ready` tức là thành công rực rỡ! 🎉

---

## 🛠 5. Thao tác hàng ngày (Cheatsheet)

**Truy cập thẳng vào máy ảo (SSH):**
Bạn muốn vào bên trong node K8s để soi Route table, IPVS hay iptables? Không cần pass:
```bash
multipass shell k8s-master
multipass shell k8s-worker1
```

**Chạy lệnh nhanh trên máy ảo mà không cần vào shell:**
```bash
multipass exec k8s-master -- ip route show
multipass exec k8s-master -- crictl pods
```

**Xem IP của các máy ảo:**
```bash
multipass list
```

---

## 🧹 6. Xoá/Reset Lab

Khi bạn làm sai quá nhiều thứ không thể gỡ, hoặc khi bạn cần **chuyển CNI** từ bài học này sang bài học khác (VD: Xoá Flannel cài Cilium).

**Reset Cluster nhưng GIỮ LẠI máy ảo (Rất Nhanh!):**
```bash
./reset-lab.sh
```
Lệnh này sẽ clean cluster (`kubeadm reset`), tự động xóa các network rác của CNI cũ và khởi động lại (reboot) các node. Trả lại bạn 3 máy ảo Ubuntu "trắng tinh khôi" cài sẵn tools. 
Sau đó, bạn có thể chạy lại `kubeadm init` (có hướng dẫn in ra màn hình khi chạy lệnh reset).

**Xóa sạch sẽ hoàn toàn (Làm lại từ đầu):**
Nếu muốn trả lại tài nguyên cho máy tính, hoặc lab bị lỗi nặng:
```bash
./reset-lab.sh --purge
```
Lệnh này sẽ xóa toàn bộ 3 máy ảo K8s và dọn rác của Multipass. Sau đó bạn có thể chạy `./setup-lab.sh` để bắt đầu một vòng đời mới.

---

## 🆘 7. Troubleshooting (Bắt Bệnh Nhanh)

- **Lỗi `command not found: multipass`**: Do bạn chưa cài Multipass hoặc lỗi PATH. Hãy kiểm tra lại phần chuẩn bị.
- **Báo lỗi `The connection to the server ... was refused`**: Master node chưa khởi động xong hoặc bị sập. Hãy chạy `multipass shell k8s-master` và kiểm tra lệnh `sudo systemctl status kubelet`.
- **Worker node không lên trạng thái `Ready`**: Thường do CNI chưa chạy lên thành công. Chạy `kubectl get pods -n kube-system` để xem Pod CNI đang gặp lỗi gì.
- **Node khởi động xong nhưng cài k8s thất bại**: Trong một số trường hợp mạng không ổn định, file `cloud-init` không tải được package. Hãy xoá lab (`./reset-lab.sh --purge`) và chạy lại khi mạng mạnh hơn.

Chúc bạn có những giờ phút vọc vạch network Kubernetes thật thú vị! 🚀
