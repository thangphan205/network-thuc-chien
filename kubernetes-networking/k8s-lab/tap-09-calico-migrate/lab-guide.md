# Lab Tập 9: Cài đặt cụm Calico CNI mới hoàn toàn bằng Multipass

Bài thực hành này hướng dẫn bạn khởi tạo một cụm Kubernetes sạch từ đầu bằng Multipass, thực hiện bootstrap cụm bằng `kubeadm` và cài đặt **Calico CNI** qua Tigera Operator. Đây sẽ là môi trường lab chuẩn và sạch sẽ để chuẩn bị cho chuỗi các bài học chuyên sâu tiếp theo về Calico (từ Tập 10 đến Tập 24).

---

## 🛠 Yêu cầu chuẩn bị

Để đảm bảo không bị xung đột với các cấu hình cũ của cụm Flannel từ những bài trước, chúng ta nên xóa sạch cụm máy ảo cũ và tạo lại từ đầu.

1. **Xóa cụm máy ảo cũ (nếu có):**
   ```bash
   multipass delete controlplane worker1 worker2
   multipass purge
   ```

2. **Khởi tạo 3 máy ảo mới sạch hoàn toàn:**
   Sử dụng script `./setup-lab.sh` có sẵn trong thư mục `tap-00-setup-lab` để tự động tạo 3 máy ảo Ubuntu 26.04 (`controlplane`, `worker1`, `worker2`) và tự động cài đặt các công cụ nền tảng (kubelet, kubeadm, kubectl, containerd):
   ```bash
   cd ../tap-00-setup-lab
   chmod +x setup-lab.sh
   ./setup-lab.sh
   cd ../tap-09-calico-migrate
   ```

---

## 🔬 Thí nghiệm 1: Khởi tạo cụm Kubernetes & Cài đặt Calico CNI

Thí nghiệm này sẽ hướng dẫn bạn bootstrap cụm K8s qua `kubeadm` và cài đặt Calico CNI để đưa các node từ trạng thái `NotReady` sang `Ready`.

### Bước 1: Khởi tạo Control Plane

1. **SSH vào máy ảo `controlplane`:**
   ```bash
   multipass shell controlplane
   ```

2. **Khởi tạo Control Plane bằng Kubeadm:**
   Chạy lệnh `kubeadm init` với dải CIDR chuẩn dành cho Pod (`10.244.0.0/16`) và tự động lấy IP nội bộ của card mạng `eth0` làm địa chỉ API Server:
   ```bash
   sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$(ip route get 1.1.1.1 | awk '{print $7}')
   ```

3. **Cấu hình kubeconfig cho user `ubuntu`:**
   Chạy các lệnh sau ngay trên `controlplane` để có thể sử dụng công cụ `kubectl`:
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

---

### Bước 2: Join các node Worker vào cụm

1. **Lấy câu lệnh join cụm:**
   Sau khi khởi tạo thành công trên `controlplane`, bạn sẽ nhận được một dòng lệnh có dạng:
   ```bash
   sudo kubeadm join 192.168.64.X:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
   ```

2. **SSH vào `worker1` và chạy lệnh join cụm:**
   ```bash
   multipass shell worker1
   # Dán câu lệnh join của bạn (thêm sudo):
   sudo kubeadm join 192.168.64.X:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
   ```

3. **SSH vào `worker2` và chạy lệnh join cụm:**
   ```bash
   multipass shell worker2
   # Dán câu lệnh join của bạn (thêm sudo):
   sudo kubeadm join 192.168.64.X:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
   ```

4. **Kiểm tra trạng thái các node trên `controlplane`:**
   Quay lại terminal của `controlplane` và chạy:
   ```bash
   kubectl get nodes
   ```
   **Kết quả mong đợi:**
   ```
   NAME           STATUS     ROLES           AGE   VERSION
   controlplane   NotReady   control-plane   2m    v1.36.1
   worker1        NotReady   <none>          1m    v1.36.1
   worker2        NotReady   <none>          1m    v1.36.1
   ```
   > **Giải thích:** Tất cả các Node đều ở trạng thái `NotReady` vì cụm chưa được cài đặt CNI (Container Network Interface), hệ thống mạng K8s chưa hoạt động.

---

### Bước 3: Cài đặt Calico CNI qua Tigera Operator

1. **Cài đặt Tigera Operator (Trình quản lý vòng đời Calico):**
   ```bash
   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
   ```

2. **Tạo Custom Resource (CR) để cấu hình mạng Calico:**
   Tạo file cấu hình với IP Pool trùng khớp hoàn toàn với cấu hình `--pod-network-cidr=10.244.0.0/16` mà chúng ta truyền vào kubeadm ban đầu:
   ```bash
   kubectl create -f - <<'EOF'
   apiVersion: operator.tigera.io/v1
   kind: Installation
   metadata:
     name: default
   spec:
     calicoNetwork:
       ipPools:
       - blockSize: 26
         cidr: 10.244.0.0/16
         encapsulation: VXLANCrossSubnet
         natOutgoing: Enabled
         nodeSelector: all()
   EOF
   ```

---

### Bước 4: Theo dõi và Kiểm chứng kết quả

1. **Theo dõi các Pod của Calico khởi động trong namespace `calico-system`:**
   ```bash
   watch kubectl get pods -n calico-system
   ```
   *Đợi khoảng 1-2 phút cho đến khi tất cả các Pod (calico-node, calico-kube-controllers,...) chuyển sang trạng thái `Running`.*

2. **Verify các node đã chuyển sang trạng thái `Ready`:**
   ```bash
   kubectl get nodes
   ```
   **Kết quả mong đợi:**
   ```
   NAME           STATUS   ROLES           AGE   VERSION
   controlplane   Ready    control-plane   5m    v1.36.1
   worker1        Ready    <none>          4m    v1.36.1
   worker2        Ready    <none>          4m    v1.36.1
   ```
   🎉 Cụm máy ảo chạy Calico CNI của bạn đã được cài đặt và hoạt động hoàn hảo!

---

## 💥 Thí nghiệm 2: Verify NetworkPolicy được enforce thực sự

Để kiểm chứng tính năng vượt trội nhất của Calico so với Flannel (khả năng áp dụng NetworkPolicy thực sự), chúng ta tiến hành kịch bản kiểm thử bảo mật.

### 1. Triển khai 2 Pod thử nghiệm nằm ở hai node khác nhau:
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: database
  labels:
    app: database
spec:
  nodeName: worker2
  containers:
  - name: db
    image: nicolaka/netshoot
    command: ["nc", "-lk", "-p", "5432"]
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  nodeName: worker1
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

# Đợi 2 pod chuyển sang trạng thái Ready
kubectl wait --for=condition=Ready pod/database pod/frontend --timeout=90s
```

### 2. Kiểm tra kết nối trước khi áp dụng NetworkPolicy:
```bash
DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')
kubectl exec frontend -- nc -zv $DB_IP 5432
# Kết quả mong đợi: 
# Connection to 10.244.2.X 5432 port succeeded! ✅ (kết nối thông suốt)
```

### 3. Áp dụng chính sách bảo mật "Default Deny" (Khóa toàn bộ kết nối):
```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

### 4. Kiểm tra lại kết nối sau khi áp dụng chính sách:
```bash
kubectl exec frontend -- nc -zv -w 3 $DB_IP 5432
# Kết quả mong đợi:
# nc: connect to 10.244.2.X port 5432 (tcp) timed out: Operation now in progress ❌
```
> **Nhận xét:** Calico đã thực thi (enforce) chính sách chặn chính xác. Đây là điều mà Flannel không thể làm được ở Tập 10 do thiếu cơ chế Security Engine.

---

## 🔬 Thí nghiệm 3: Kiểm tra iptables chains do Felix tạo

Felix là thành phần chạy trên từng Node của Calico chịu trách nhiệm biên dịch NetworkPolicy thành cấu hình iptables ở cấp độ Linux kernel.

1. **SSH vào `worker1`:**
   ```bash
   multipass shell worker1
   ```

2. **Liệt kê các chains trong iptables do Calico quản lý:**
   ```bash
   sudo iptables -L | grep "^Chain cali"
   ```
   **Kết quả:** Bạn sẽ thấy các chain có tiền tố `cali-` như `cali-FORWARD`, `cali-INPUT`, `cali-OUTPUT`, và đặc biệt là các chain dạng `cali-fw-<endpoint>` (egress rules của Pod) và `cali-tw-<endpoint>` (ingress rules của Pod).

3. **Xem các rule chuyển tiếp trong chain `cali-FORWARD`:**
   ```bash
   sudo iptables -L cali-FORWARD -n --line-numbers
   ```
   Felix tạo ra các hook để bắt và lọc gói tin đi qua các card mạng ảo của Pod ngay lập tức khi gói tin đi vào hoặc đi ra.

4. **Đếm số lượng rules liên quan đến Calico để thấy mức độ kiểm soát:**
   ```bash
   sudo iptables -L | grep -c "cali"
   # Kết quả: Một lượng lớn rules (hàng trăm dòng) được tự động sinh ra và đồng bộ realtime!
   ```

---

## 🧹 Dọn dẹp môi trường thực hành

Để chuẩn bị môi trường sạch sẽ cho bài tiếp theo, hãy xóa các Pod và Policy thử nghiệm (nhưng **giữ nguyên Calico CNI**):
```bash
kubectl delete pod database frontend
kubectl delete networkpolicy default-deny
```

---

## ✅ Tổng kết

Qua bài thực hành này, bạn đã tự tay:
1. **Khởi dựng cụm Kubernetes** sạch hoàn toàn từ đầu sử dụng Kubeadm và Multipass.
2. **Cài đặt thành công Calico CNI** sử dụng công nghệ tiên tiến **Tigera Operator**.
3. **Chứng minh năng lực bảo mật mạng** của Calico qua việc ép thành công NetworkPolicy (Default Deny), giảm thiểu rủi ro lan rộng mã độc (Blast Radius).
4. **Hiểu cách thức hoạt động tầng thấp** của bộ điều khiển chính sách **Felix** thông qua hệ thống Linux `iptables` hooks.
