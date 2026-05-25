---
marp: true
theme: default
paginate: true
style: |
  section { font-family: 'Segoe UI', sans-serif; font-size: 22px; background: #0d1021; color: #e2e8f0; }
  h1 { color: #a78bfa; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #34d399; font-size: 1.4em; border-bottom: 2px solid #34d399; padding-bottom: 0.2em; }
  h3 { color: #fbbf24; font-size: 1.1em; }
  code { background: #1a1a35; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1a1a35; border-left: 4px solid #a78bfa; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
  th { background: #2d1b69; color: #e9d5ff; padding: 10px 14px; font-weight: 600; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a2050; color: #e2e8f0; background: #151530; }
  tr:nth-child(even) td { background: #1e1e40; }
  blockquote { border-left: 4px solid #fbbf24; padding-left: 16px; color: #cbd5e1; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  pre .hljs-comment, pre .hljs-meta { color: #7dd3fc; }
  pre .hljs-keyword, pre .hljs-selector-tag { color: #f9a8d4; }
  pre .hljs-string, pre .hljs-attr { color: #86efac; }
  pre .hljs-number, pre .hljs-literal { color: #fde68a; }
  pre .hljs-variable, pre .hljs-template-variable { color: #c4b5fd; }
  pre .hljs-built_in, pre .hljs-name { color: #67e8f9; }
  pre .hljs-subst { color: #e2e8f0; }
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
  section.warn { background: linear-gradient(135deg, #1a0800 0%, #0d1021 100%); }
  section.warn h2 { color: #f87171; border-bottom-color: #f87171; }
---

<!-- _class: ep -->

# Tập 9
## Cài đặt cụm Calico CNI mới hoàn toàn bằng Multipass

**Phần 2 — Calico** · `#calico` `#bootstrap` `#kubeadm` `#NetworkPolicy` `#security`

---

## Mục tiêu tập này

- Hiểu rõ rủi ro bảo mật **Lateral Movement** & Khái niệm **Blast Radius**
- Khởi tạo cụm Kubernetes sạch từ đầu và join các node sử dụng Multipass
- Cài đặt **Calico CNI** qua Tigera Operator (`10.244.0.0/16` CIDR)
- Chứng thực cơ chế bảo mật hoạt động thực sự qua **Default Deny Policy**
- Giải phẫu các chains `cali-*` trong iptables do Felix đồng bộ xuống kernel

---

## Mối đe dọa: Lateral Movement & Blast Radius

**Lateral Movement (Di chuyển ngang):**
Khi attacker tấn công thành công một Pod công khai (ví dụ Frontend có lỗ hổng), họ sẽ dùng Pod đó làm bàn đạp để quét và tấn công các Pod nội bộ khác (Database, Payment Services, DNS).

```
Flannel (mặc định không enforce NetworkPolicy):
  [Frontend compromised] ────(Mạng không chặn)────► [Internal DB] (Bị hack!)
  Blast Radius = N-1 (tấn công được toàn bộ các dịch vụ còn lại)
```

**Bảo mật Least Privilege (Quyền hạn tối thiểu):**
```
Calico + Default Deny + Least Privilege:
  Mỗi Pod mặc định bị KHÓA hết kết nối, chỉ được cho phép nói chuyện với đúng dịch vụ được chỉ định.
  Blast Radius = Rất nhỏ (chỉ giới hạn trong phạm vi dịch vụ được khai báo)
```

---

## Kiến trúc 3 thành phần chính của Calico

```
                 ┌──────────────────────────────────────┐
                 │ Tigera Operator (Quản lý Lifecycle)  │
                 └──────────────────┬───────────────────┘
                                    │
                          ┌─────────┼─────────┐
                          │         │         │
                     ┌────▼───┐ ┌───▼──┐ ┌────▼────┐
                     │ Felix  │ │ BIRD │ │  Typha  │
                     │ Policy │ │  BGP │ │  Cache  │
                     │ Engine │ │daemon│ │  Node   │
                     └────────┘ └──────┘ └─────────┘
```
- **Felix:** Bộ não chính chạy trên mỗi Node, nhận diện NetworkPolicy từ API Server và dịch trực tiếp thành các rules bảo mật trong Linux kernel (`iptables`/`eBPF`).
- **BIRD:** BGP Daemon chịu trách nhiệm chia sẻ routing table giữa các node (L3 routing).
- **Typha:** Bộ đệm giúp giảm tải truy vấn cho API Server khi cụm scale lớn.

---

<!-- _class: lab -->

## Lab 1: Khởi dựng cụm K8s sạch & Join Worker Nodes

**Bước 1: Khởi dựng lại cụm máy ảo mới hoàn toàn**
```bash
# Xóa sạch cụm máy ảo cũ để tránh xung đột cấu hình mạng
multipass delete controlplane worker1 worker2 && multipass purge

# Tạo mới 3 VM bằng script setup của Tập 00
cd ../tap-00-setup-lab && ./setup-lab.sh && cd ../tap-09-calico-migrate
```

**Bước 2: Khởi tạo Control Plane & Cấu hình kubeconfig**
```bash
multipass shell controlplane

# Bootstrap cụm với kubeadm và dải CIDR chuẩn dành cho Pod
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$(ip route get 1.1.1.1 | awk '{print $7}')

# Cấu hình kubectl cho user không có quyền root
mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

<!-- _class: lab -->

## Lab 1 (tiếp): Join Node & Xem trạng thái thiếu CNI

**Bước 3: Join các node worker vào cụm**
```bash
# SSH vào worker1 và chạy câu lệnh join nhận được từ controlplane
multipass shell worker1
sudo kubeadm join 192.168.64.X:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# Thực hiện tương tự với worker2
multipass shell worker2
sudo kubeadm join 192.168.64.X:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

**Bước 4: Kiểm tra trạng thái nodes trên `controlplane`**
```bash
kubectl get nodes
# NAME           STATUS     ROLES           AGE   VERSION
# controlplane   NotReady   control-plane   2m    v1.36.1
# worker1        NotReady   <none>          1m    v1.36.1
# worker2        NotReady   <none>          1m    v1.36.1
# --> STATUS = "NotReady" do chưa có CNI (Container Network Interface) hoạt động!
```

---

<!-- _class: lab -->

## Lab 1 (tiếp): Cài đặt Calico CNI bằng Tigera Operator

**Bước 5: Cài đặt Tigera Operator & Apply Custom Resource cấu hình Calico**
```bash
# 1. Cài đặt Tigera Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml

# 2. Định nghĩa Custom Resource cấu hình Calico (khớp CIDR 10.244.0.0/16)
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

**Bước 6: Xác thực nodes chuyển sang trạng thái "Ready"**
```bash
watch kubectl get pods -n calico-system  # Chờ toàn bộ Pod sang trạng thái Running
kubectl get nodes                       # Mọi node chuyển sang "Ready"!
```

---

<!-- _class: lab -->

## Lab 2: Kiểm chứng tính năng NetworkPolicy Enforce

**Bước 1: Triển khai Pod database (worker2) & Pod frontend (worker1)**
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: database
  labels: { app: database }
spec:
  nodeName: worker2
  containers: [ { name: db, image: nicolaka/netshoot, command: ["nc", "-lk", "-p", "5432"] } ]
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels: { app: frontend }
spec:
  nodeName: worker1
  containers: [ { name: app, image: nicolaka/netshoot, command: ["sleep", "infinity"] } ]
EOF
```

**Bước 2: Test kết nối thông thường (kết nối thành công)**
```bash
DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')
kubectl exec frontend -- nc -zv $DB_IP 5432
# Connection to 10.244.2.X 5432 port succeeded! ✅
```

---

<!-- _class: lab -->

## Lab 2 (tiếp): Áp dụng Default Deny Policy & Chặn kết nối

**Bước 3: Apply chính sách Default Deny (Chặn hoàn toàn kết nối mặc định)**
```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF
```

**Bước 4: Kiểm chứng tính năng Enforce của Calico CNI**
```bash
kubectl exec frontend -- nc -zv -w 3 $DB_IP 5432
# nc: connect to 10.244.2.X port 5432 (tcp) timed out: Operation now in progress ❌
# --> Calico chặn đứng kết nối! (Khác biệt hoàn toàn so với Flannel ở Tập 10)
```

---

<!-- _class: lab -->

## Lab 3: Giải phẫu iptables chains Felix quản lý

**Bước 1: SSH vào `worker1` và kiểm tra các chains mang tên Calico**
```bash
multipass shell worker1
sudo iptables -L | grep "^Chain cali"
# Chain cali-FORWARD (1 references)
# Chain cali-INPUT (1 references)
# Chain cali-OUTPUT (1 references)
# Chain cali-fw-<endpoint-id>   ← Egress policy của Pod
# Chain cali-tw-<endpoint-id>   ← Ingress policy của Pod
```

**Bước 2: Xem chi tiết chain cali-FORWARD để thấy logic lọc**
```bash
sudo iptables -L cali-FORWARD -n --line-numbers
```

**Bước 3: Đếm số lượng rules chứng tỏ Felix dịch chính sách trực tiếp xuống kernel**
```bash
sudo iptables -L | grep -c "cali"
# Kết quả trả về hàng trăm rules hoạt động theo thời gian thực (realtime event-driven).
```

---

## So sánh cốt lõi: Flannel vs Calico

| Tiêu chí | Flannel | Calico |
| :--- | :--- | :--- |
| **NetworkPolicy** | Bị bỏ qua hoàn toàn | **Được enforce tuyệt đối** |
| **Blast Radius** | **Toàn bộ cluster** (N-1) | Giới hạn tối thiểu (Least Privilege) |
| **Bảo mật mặc định** | Cho phép tất cả (Allow all) | **Khóa tất cả (Deny all) qua Policy** |
| **Cơ chế hoạt động** | Chỉ chuyển tiếp packet | **Chuyển tiếp + Firewall động (Felix)** |
| **Cài đặt** | DaemonSet đơn giản | **Tigera Operator (Quản lý Lifecycle)** |

---

## Key Takeaways

```
1. Cài mới Kubernetes bằng Kubeadm luôn để trạng thái "NotReady" cho đến khi có CNI.
2. Calico CNI được cài đặt dễ dàng qua Tigera Operator với IP Pool chuẩn (10.244.0.0/16).
3. Felix là bộ não an ninh của Calico, đồng bộ NetworkPolicy thành Linux iptables/eBPF.
4. Triển khai Default Deny và Least Privilege là chìa khóa thu hẹp Blast Radius trong K8s.
```

> **Tập tiếp theo:** Giải phẫu kiến trúc Calico — Felix, BIRD, Typha hoạt động tương tác với nhau như thế nào?
