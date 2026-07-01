# Hướng dẫn dựng cụm K8s + Cilium trên Remote Servers (VPS / Dedicated Server)

Tài liệu này hướng dẫn cách cấu hình thủ công hệ điều hành, cài đặt các thành phần Kubernetes (v1.36) và deploy **Cilium ở chế độ Production** trên các máy chủ vật lý hoặc máy ảo đám mây (Cloud VMs như AWS, GCP, Azure, DigitalOcean, Hetzner, VNG Cloud, Viettel IDC, v.v.) thay vì sử dụng môi trường Multipass ở máy local.

---

## 1. Yêu cầu chuẩn bị & Cấu hình mạng

### Phần cứng tối thiểu (mỗi node)
- **CPU:** Tối thiểu 2 vCPUs (Kubernetes không chạy được trên 1 CPU).
- **RAM:** Tối thiểu 2GB (Khuyến nghị 4GB cho Control Plane).
- **Disk:** Tối thiểu 20GB.
- **Hệ điều hành:** Ubuntu 22.04 LTS hoặc 24.04 / 26.04 LTS (Khuyến nghị Ubuntu 24.04/26.04 vì sử dụng Linux Kernel 6.x+, hỗ trợ đầy đủ các tính năng eBPF mới nhất của Cilium).

### Cấu hình tường lửa (Security Group / Firewall)
Đảm bảo các cổng (port) sau được mở giữa các node trong cụm:

| Giao thức | Cổng | Mục đích |
| :--- | :--- | :--- |
| **TCP** | `6443` | Kubernetes API Server (chỉ cần mở trên Control Plane) |
| **TCP** | `2379-2380` | etcd control plane (nội bộ Control Plane) |
| **TCP** | `10250` | Kubelet API (tất cả nodes) |
| **UDP** | `8472` | Cilium VXLAN Overlay (chỉ cần nếu chọn mode VXLAN) |
| **UDP** | `51871` | Cilium WireGuard encryption (pod-to-pod) |
| **TCP** | `4244` | Hubble server (nội bộ các node chạy Cilium agent) |
| **TCP** | `4245` | Hubble Relay (nội bộ) |

---

## BƯỚC 1: Cấu hình OS & Cài Container Runtime + K8s Components
*(Chạy các lệnh dưới đây dưới quyền `root` hoặc dùng `sudo` trên **TẤT CẢ** các nodes: Control Plane & Workers)*

### 1.1 — Tắt Swap (Bắt buộc đối với Kubelet)
```bash
sudo swapoff -a
# Tắt swap vĩnh viễn trong file fstab
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### 1.2 — Load các Kernel modules cần thiết
```bash
sudo modprobe overlay
sudo modprobe br_netfilter

# Lưu cấu hình để tự động load khi reboot
sudo sh -c 'echo "overlay
br_netfilter" > /etc/modules-load.d/k8s.conf'
```

### 1.3 — Cấu hình Sysctl cho Network Routing
Cấu hình các tham số mạng để kernel cho phép forward gói tin và bridge gói tin đi qua iptables.
```bash
sudo sh -c 'echo "net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1" > /etc/sysctl.d/k8s.conf'

# Áp dụng cấu hình ngay lập tức
sudo sysctl --system
```

### 1.4 — Cài đặt Container Runtime (containerd)
```bash
# Update hệ thống và cài các package phụ trợ
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Thêm Docker GPG key và apt repo
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
CODENAME=$(lsb_release -cs)
# Fallback về noble nếu Docker chưa chính thức publish repo cho Ubuntu 26.04
curl -sf https://download.docker.com/linux/ubuntu/dists/${CODENAME}/Release -o /dev/null || CODENAME=noble

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update && sudo apt-get install -y containerd.io

# Tạo file config mặc định cho containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# QUAN TRỌNG: Cấu hình SystemdCgroup thành true
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd để nhận cấu hình mới
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 1.5 — Cài đặt Kubeadm, Kubelet và Kubectl (v1.36)
```bash
# Thêm khóa GPG của Kubernetes repo
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Thêm Kubernetes APT repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Cài đặt các package và giữ phiên bản (apt-mark hold)
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl cri-tools
sudo apt-mark hold kubelet kubeadm kubectl

# Cấu hình crictl trỏ về containerd endpoint
sudo crictl config runtime-endpoint unix:///run/containerd/containerd.sock
sudo crictl config image-endpoint unix:///run/containerd/containerd.sock
```

---

## BƯỚC 2: Khởi tạo Control Plane Node
*(Chạy trên node **Control Plane / Master** duy nhất)*

### 2.1 — Xác định IP giao diện mạng nội bộ (Internal IP)
Cilium cần kết nối trực tiếp đến API Server qua IP nội bộ này. Hãy xác định địa chỉ IP Private của node Control Plane (ví dụ: `10.128.0.10`).

```bash
# Xem các IP đang có trên máy
ip -4 addr show
```

### 2.2 — Khởi tạo Kubeadm không cài đặt Kube-proxy
Để Cilium thay thế hoàn toàn `kube-proxy` (KubeProxyReplacement), ta cần bỏ qua pha cài đặt kube-proxy addon của kubeadm:

```bash
export CONTROL_PLANE_IP="<IP-NỘI-BỘ-CONTROL-PLANE>" # Thay bằng IP thực tế của bạn
export POD_CIDR="10.244.0.0/16"

sudo kubeadm init \
  --apiserver-advertise-address=$CONTROL_PLANE_IP \
  --pod-network-cidr=$POD_CIDR \
  --skip-phases=addon/kube-proxy
```

> [!NOTE]
> Node Control Plane lúc này sẽ ở trạng thái `NotReady` cho đến khi ta hoàn tất cài đặt Cilium ở Bước 5.

### 2.3 — Cấu hình Kubectl cho User thường
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 2.4 — Lấy lệnh Join và Token cho Worker Nodes
```bash
kubeadm token create --print-join-command
# Dòng output có dạng:
# kubeadm join 10.128.0.10:6443 --token xxxxx --discovery-token-ca-cert-hash sha256:xxxxx
```

---

## BƯỚC 3: Join các Node Worker vào Cluster
*(Chạy trên các node **Worker**)*

Dùng lệnh join nhận được ở Bước 2.4 chạy với quyền `sudo`:

```bash
sudo kubeadm join 10.128.0.10:6443 --token xxxxx --discovery-token-ca-cert-hash sha256:xxxxx
```

Sau khi join xong, trên **Control Plane**, bạn kiểm tra trạng thái các node (tất cả đều đang ở trạng thái `NotReady` vì chưa có CNI):
```bash
kubectl get nodes
# controlplane   NotReady   control-plane
# worker1        NotReady   <none>
# worker2        NotReady   <none>
```

---

## BƯỚC 4: Cài đặt Helm & Cilium / Hubble CLI
*(Chạy trên node **Control Plane**)*

```bash
# Cài đặt Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Cài đặt Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=$(dpkg --print-architecture) # Tự động phát hiện amd64 hoặc arm64
curl -L --fail --remote-name-all \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz"{,.sha256sum}
sha256sum --check "cilium-linux-${CLI_ARCH}.tar.gz.sha256sum"
sudo tar xzvf "cilium-linux-${CLI_ARCH}.tar.gz" --directory /usr/local/bin
rm "cilium-linux-${CLI_ARCH}.tar.gz" "cilium-linux-${CLI_ARCH}.tar.gz.sha256sum"

# Cài đặt Hubble CLI
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --fail --remote-name-all \
  "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-${CLI_ARCH}.tar.gz"{,.sha256sum}
# Note: Đôi khi repo hubble-cli đổi địa chỉ tải về, ta có thể dùng link github chính thức:
curl -L --fail --remote-name-all \
  "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-${CLI_ARCH}.tar.gz"{,.sha256sum}
sha256sum --check "hubble-linux-${CLI_ARCH}.tar.gz.sha256sum"
sudo tar xzvf "hubble-linux-${CLI_ARCH}.tar.gz" --directory /usr/local/bin
rm "hubble-linux-${CLI_ARCH}.tar.gz" "hubble-linux-${CLI_ARCH}.tar.gz.sha256sum"
```

---

## BƯỚC 5: Deploy Cilium (Chọn 1 trong 2 chế độ mạng)
*(Chạy trên node **Control Plane**)*

Dựa trên sơ đồ hạ tầng mạng của các VPS/Remote Servers của bạn, chọn một trong hai phương án triển khai dưới đây:

### OPTION A: Triển khai với Native Routing (Direct Routing)
> [!IMPORTANT]
> **Điều kiện sử dụng:** Tất cả các VPS/Server phải nằm chung một mạng LAN ảo (cùng L2 subnet / VPC) và hạ tầng mạng của Cloud Provider cho phép chuyển tiếp gói tin có IP nguồn khác với IP của node (không filter Source/Destination IP. Đối với AWS/GCP, bạn phải tắt tính năng **Source/Destination Check** trên các Instance card mạng).

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

export CONTROL_PLANE_IP="<IP-NỘI-BỘ-CONTROL-PLANE>"
export POD_CIDR="10.244.0.0/16"

helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${CONTROL_PLANE_IP}" \
  --set k8sServicePort=6443 \
  --set routingMode=native \
  --set ipv4NativeRoutingCIDR="${POD_CIDR}" \
  --set autoDirectNodeRoutes=true \
  --set ipam.mode=cluster-pool \
  --set "ipam.operator.clusterPoolIPv4PodCIDRList=${POD_CIDR}" \
  --set ipam.operator.clusterPoolIPv4MaskSize=24 \
  --set bpf.masquerade=true \
  --set socketLB.enabled=true \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enableOpenMetrics=true \
  --set "hubble.metrics.enabled={dns,drop,tcp,flow,port-distribution,icmp,httpV2}" \
  --set operator.replicas=1
```

---

### OPTION B: Triển khai với Overlay/Tunneling Mode (Mặc định & Khuyên dùng trên Cloud Public)
> [!TIP]
> **Điều kiện sử dụng:** Khuyên dùng nếu các node nằm ở các subnet khác nhau, các VPS thuộc các provider khác nhau, hoặc hạ tầng Cloud chặn Native Routing (AWS/GCP chưa tắt Source/Destination check). Cilium sẽ sử dụng công nghệ đóng gói VXLAN để truyền tải traffic giữa các pod một cách độc lập với hạ tầng mạng bên dưới.

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

export CONTROL_PLANE_IP="<IP-NỘI-BỘ-CONTROL-PLANE>"
export POD_CIDR="10.244.0.0/16"

helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${CONTROL_PLANE_IP}" \
  --set k8sServicePort=6443 \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=cluster-pool \
  --set "ipam.operator.clusterPoolIPv4PodCIDRList=${POD_CIDR}" \
  --set ipam.operator.clusterPoolIPv4MaskSize=24 \
  --set bpf.masquerade=true \
  --set socketLB.enabled=true \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enableOpenMetrics=true \
  --set "hubble.metrics.enabled={dns,drop,tcp,flow,port-distribution,icmp,httpV2}" \
  --set operator.replicas=1
```

*Lưu ý:* Ở chế độ Tunneling (Overlay), Cilium sẽ tự động đóng gói (encapsulate) gói tin Pod qua giao thức VXLAN trên cổng `8472 UDP`, do đó bạn không cần cấu hình `autoDirectNodeRoutes=true` hay lo lắng về việc cấu hình định tuyến của các VPS.

---

## BƯỚC 6: Kiểm tra và Xác thực hệ thống
*(Chạy trên node **Control Plane**)*

### 6.1 — Chờ hệ thống khởi tạo hoàn tất
```bash
cilium status --wait
```

### 6.2 — Xác thực toàn bộ Nodes đã Ready và Pods hoạt động
```bash
# Kiểm tra Nodes
kubectl get nodes -o wide

# Kiểm tra Pods trong namespace kube-system (không có kube-proxy)
kubectl get pods -n kube-system -o wide
```

### 6.3 — Xác thực tính năng mã hóa WireGuard hoạt động
```bash
CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1)
kubectl -n kube-system exec -it $CILIUM_POD -- cilium encrypt status
```

### 6.4 — Chạy Connectivity Test
Cilium cung cấp bộ test tự động kiểm tra toàn bộ connectivity giữa các pod và các service trong cluster:
```bash
cilium connectivity test
```

Bây giờ cụm K8s chạy Cilium Production trên các máy chủ Remote đã hoàn tất. Bạn có thể tiếp tục thực hành từ **Thực nghiệm 5** và **Thực nghiệm 6** trong file chính: [lab-guide.md](file:///Users/thangpa/projects/9ping/network-thuc-chien/kubernetes-networking/k8s-lab/tap-23-cilium-why/lab-guide.md).
