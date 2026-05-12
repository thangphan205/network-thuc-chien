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
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; margin-top: 0.3em; }
  section.ep p { color: #94a3b8; font-size: 0.9em; margin-top: 12px; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
  section.lab h2 { color: #34d399; }
  section.warn { background: linear-gradient(135deg, #1a0a00 0%, #0d1021 100%); }
  section.warn h2 { color: #fb923c; border-bottom-color: #fb923c; }
---

<!-- _class: ep -->

# Lab Setup — Multipass + cloud-init
## Ubuntu 26.04 · Kubernetes 1.32 · Dùng cho toàn bộ khóa học

Chạy một lần — tất cả 45 tập dùng cluster này

---

## Yêu cầu máy host

| Resource | Tối thiểu | Khuyến nghị |
| :--- | :--- | :--- |
| RAM | 8 GB | **16 GB** |
| CPU | 4 core | **8 core** |
| Disk | 60 GB free | **100 GB free** |
| OS | macOS 13+ / Windows 10+ | macOS M-series |

```bash
# Cài Multipass (macOS)
brew install multipass

multipass version
# multipass  1.14.x
# multipassd 1.14.x
```

---

## cloud-init là gì?

```
cloud-init = Standard initialization system cho cloud VMs
  → Chạy tự động khi VM boot lần đầu
  → Không cần SSH vào cài tay

Thay vì:
  multipass launch → ssh vào → chạy script cài containerd...

cloud-init:
  multipass launch --cloud-init k8s-node.yaml
  → VM tự cài containerd, kubeadm, kernel modules
  → Khi "Running" là đã ready hoàn toàn!

File k8s-node.yaml = "bản thiết kế VM"
  → Version-controlled
  → Reproducible
  → Idempotent
```

---

## Tạo cloud-init file: k8s-node.yaml

```bash
cat > /tmp/k8s-node.yaml << 'EOF'
#cloud-config

# Tắt swap (K8s yêu cầu)
bootcmd:
  - swapoff -a

# Xóa swap entry khỏi fstab
runcmd:
  - sed -i '/\bswap\b/d' /etc/fstab

# Kernel modules cần cho K8s networking
modules:
  - overlay
  - br_netfilter

write_files:
  # Load modules tự động khi boot
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  # Sysctl cho bridge networking và IP forwarding
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

  # containerd config: bật SystemdCgroup
  - path: /etc/containerd/config.toml
    content: |
      version = 2
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true

  # Kubernetes apt repo
  - path: /etc/apt/sources.list.d/kubernetes.list
    content: |
      deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /
EOF
```

---

## cloud-init (tiếp): packages & runcmd

```bash
cat >> /tmp/k8s-node.yaml << 'EOF'

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gpg
  - containerd

package_update: true
package_upgrade: false

runcmd:
  # Apply sysctl ngay
  - sysctl --system

  # containerd: generate default config nếu file chưa đầy đủ
  - mkdir -p /etc/containerd
  - containerd config default > /tmp/containerd-default.toml
  - |
    if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml 2>/dev/null; then
      cp /tmp/containerd-default.toml /etc/containerd/config.toml
      sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    fi
  - systemctl restart containerd
  - systemctl enable containerd

  # Kubernetes signing key
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  # Install K8s tools
  - apt-get update -q
  - apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl
  - systemctl enable kubelet

  # nicola/netshoot image pull (cache trước để lab nhanh)
  - crictl pull docker.io/nicolaka/netshoot || true

final_message: "K8s node ready after $UPTIME seconds"
EOF

echo "k8s-node.yaml created at /tmp/k8s-node.yaml"
```

---

## Launch 3 VMs với cloud-init

```bash
# Launch song song — cloud-init chạy tự động trong background
multipass launch 26.04 \
  --name k8s-master \
  --cpus 2 --memory 4G --disk 30G \
  --cloud-init /tmp/k8s-node.yaml &

multipass launch 26.04 \
  --name k8s-worker1 \
  --cpus 2 --memory 2G --disk 20G \
  --cloud-init /tmp/k8s-node.yaml &

multipass launch 26.04 \
  --name k8s-worker2 \
  --cpus 2 --memory 2G --disk 20G \
  --cloud-init /tmp/k8s-node.yaml &

wait
echo "All VMs launched!"

# Verify: chờ cloud-init hoàn thành (3-5 phút)
multipass list
# Name         State    IPv4             Image
# k8s-master   Running  192.168.64.10    Ubuntu 26.04 LTS
# k8s-worker1  Running  192.168.64.11    Ubuntu 26.04 LTS
# k8s-worker2  Running  192.168.64.12    Ubuntu 26.04 LTS
```

---

## Kiểm tra cloud-init đã xong chưa

```bash
# Chờ cloud-init complete trên từng node
for NODE in k8s-master k8s-worker1 k8s-worker2; do
  echo "Waiting $NODE..."
  multipass exec $NODE -- \
    cloud-init status --wait
  # status: done  ← Hoàn thành
done

# Verify kubelet installed
multipass exec k8s-master -- kubelet --version
# Kubernetes v1.32.x

# Verify containerd running
multipass exec k8s-master -- systemctl is-active containerd
# active

# Verify kernel modules loaded
multipass exec k8s-master -- lsmod | grep -E "overlay|br_netfilter"
# overlay           ...
# br_netfilter      ...
```

---

<!-- _class: warn -->

## Lỗi thường gặp với cloud-init

```bash
# Nếu cloud-init báo lỗi:
multipass exec k8s-master -- cloud-init status
# status: error

# Xem log chi tiết:
multipass exec k8s-master -- sudo cat /var/log/cloud-init-output.log | tail -50

# Fix thường gặp:
# 1. apt lock: cloud-init chạy apt, bị lock
#    → Chờ thêm 1-2 phút, chạy lại status

# 2. GPG key fail: network issue
#    → multipass exec k8s-master -- sudo apt-get update

# 3. containerd version mismatch:
#    → multipass exec k8s-master -- sudo apt-get install -y containerd

# Force re-run nếu cần:
multipass exec k8s-master -- sudo cloud-init clean --reboot
```

---

## Init Kubernetes cluster

```bash
# Lấy IP master
MASTER_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
echo "Master IP: $MASTER_IP"

# Init cluster trên master
multipass exec k8s-master -- sudo kubeadm init \
  --apiserver-advertise-address=$MASTER_IP \
  --pod-network-cidr=10.244.0.0/16 \
  --node-name=k8s-master \
  2>&1 | tee /tmp/kubeadm-init.log

# Setup kubeconfig
multipass exec k8s-master -- bash -c '
  mkdir -p $HOME/.kube
  sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
  echo "export KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
'
```

---

## Join workers vào cluster

```bash
# Lấy join command từ kubeadm init output
JOIN_CMD=$(multipass exec k8s-master -- \
  sudo kubeadm token create --print-join-command)

echo "Join command: $JOIN_CMD"

# Join 2 workers
multipass exec k8s-worker1 -- sudo $JOIN_CMD &
multipass exec k8s-worker2 -- sudo $JOIN_CMD &
wait

# Label workers
multipass exec k8s-master -- kubectl label node k8s-worker1 \
  node-role.kubernetes.io/worker=worker
multipass exec k8s-master -- kubectl label node k8s-worker2 \
  node-role.kubernetes.io/worker=worker

# Verify — NotReady là đúng (chưa có CNI)
multipass exec k8s-master -- kubectl get nodes -o wide
# NAME          STATUS     ROLES           AGE
# k8s-master    NotReady   control-plane   2m
# k8s-worker1   NotReady   worker          30s
# k8s-worker2   NotReady   worker          25s
```

---

## Copy kubeconfig về macOS host

```bash
# Lấy kubeconfig về máy local để dùng kubectl từ macOS
multipass exec k8s-master -- cat ~/.kube/config \
  > ~/.kube/k8s-lab-config

# Sửa server address (từ localhost sang IP thực)
MASTER_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
sed -i '' "s/127.0.0.1/$MASTER_IP/g" ~/.kube/k8s-lab-config

# Set KUBECONFIG
export KUBECONFIG=~/.kube/k8s-lab-config

# Test từ macOS
kubectl get nodes
# NAME          STATUS     ROLES           AGE
# k8s-master    NotReady   control-plane   3m
# ...

# Add vào ~/.zshrc để persist
echo 'export KUBECONFIG=~/.kube/k8s-lab-config' >> ~/.zshrc
```

---

## Cài CNI: chọn theo tập học

```bash
# Flannel (Tập 6-10):
multipass exec k8s-master -- kubectl apply -f \
  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Calico (Tập 11-26):
multipass exec k8s-master -- kubectl apply -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# Cilium (Tập 27-43):
multipass exec k8s-master -- bash -c '
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm repo add cilium https://helm.cilium.io/
  helm install cilium cilium/cilium \
    --namespace kube-system \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
'

# Sau khi cài CNI → nodes chuyển sang Ready
multipass exec k8s-master -- kubectl get nodes
# NAME          STATUS   ROLES           AGE
# k8s-master    Ready    control-plane   5m   ✅
```

---

## Alias và shortcuts tiện lợi

```bash
# Thêm vào ~/.zshrc trên macOS
cat >> ~/.zshrc << 'EOF'

# K8s Lab shortcuts
alias km='multipass exec k8s-master -- kubectl'
alias ms='multipass shell k8s-master'
alias mlist='multipass list'

# kubectl aliases
alias k='kubectl'
alias kgp='kubectl get pods -o wide --all-namespaces'
alias kgn='kubectl get nodes -o wide'
alias klog='kubectl logs -f'

# Lab helpers
lab-reset-cni() {
  multipass exec k8s-master -- sudo kubeadm reset -f
  for n in k8s-worker1 k8s-worker2; do
    multipass exec $n -- sudo kubeadm reset -f
  done
  echo "Cluster reset. Run kubeadm init again."
}

lab-info() {
  echo "Master IP: $(multipass info k8s-master | grep IPv4 | awk '{print $2}')"
  echo "Worker1 IP: $(multipass info k8s-worker1 | grep IPv4 | awk '{print $2}')"
  echo "Worker2 IP: $(multipass info k8s-worker2 | grep IPv4 | awk '{print $2}')"
  kubectl get nodes -o wide
}
EOF

source ~/.zshrc
```

---

## Reset & cleanup

```bash
# Xóa cluster nhưng giữ VMs (để đổi CNI)
for NODE in k8s-master k8s-worker1 k8s-worker2; do
  multipass exec $NODE -- sudo kubeadm reset -f
  multipass exec $NODE -- sudo rm -rf /etc/cni/net.d /var/lib/cni
done

# Xóa toàn bộ VMs (end of course)
multipass delete k8s-master k8s-worker1 k8s-worker2
multipass purge

# Recreate từ đầu (cloud-init cached — nhanh hơn lần đầu)
multipass launch 26.04 --name k8s-master \
  --cpus 2 --memory 4G --disk 30G \
  --cloud-init /tmp/k8s-node.yaml
# ...
```

> **cloud-init file: tái sử dụng cho mọi tập. Thay CNI bằng `kubeadm reset` + re-init.**
