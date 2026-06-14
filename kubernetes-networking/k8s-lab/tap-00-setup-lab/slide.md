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
  .topo { display: flex; justify-content: center; align-items: center; gap: 40px; margin: 20px 0; }
  .node { background: #1a1a35; border: 2px solid #a78bfa; border-radius: 10px; padding: 16px 24px; text-align: center; min-width: 130px; }
  .node.master { border-color: #34d399; }
  .node .label { font-size: 0.75em; color: #94a3b8; margin-top: 4px; }
  .arrow { color: #4b5563; font-size: 1.4em; }
---

<!-- _class: ep -->

# Tập 0: Setup Lab Environment
## Kubernetes Networking — 45 tập thực hành

Cluster chạy local · Ubuntu 26.04 · Kubernetes 1.36 · Multipass

---

## Tổng quan lab

**1 cluster Kubernetes · 3 node · chạy trên máy tính của bạn**

```
┌─────────────────────────────────────────────────────────────┐
│  macOS / Windows Host  (kubectl, helm, multipass CLI)       │
│                                                             │
│  ┌──────────────────┐  ┌────────────────┐  ┌────────────┐   │
│  │   controlplane   │  │    worker1     │  │   worker2  │   │
│  │  control-plane   │  │    worker      │  │   worker   │   │
│  │ 2 CPU · 2 GB RAM │  │ 1 CPU · 1.5 GB │  │1 CPU·1.5 GB│   │
│  └──────────────────┘  └────────────────┘  └────────────┘   │
│         Ubuntu 26.04 LTS · containerd · kubelet             │
└─────────────────────────────────────────────────────────────┘
```

> Multipass = hypervisor nhẹ, chạy VM Ubuntu thật trên macOS/Windows — không cần Docker Desktop hay cloud account.

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

# Verify
multipass version
# multipass  1.16.x
```

---

## Cấu trúc lab files

```
tap-00-setup-lab/
├── k8s-cloud-init.yaml  ← cloud-init: "bản thiết kế" chung mỗi VM
├── setup-lab.sh         ← Router tự động nhận diện CPU & điều hướng
├── setup-lab-arm.sh     ← Dành riêng cho chip ARM (Apple Silicon)
├── setup-lab-amd.sh     ← Dành riêng cho chip AMD/Intel (x86_64)
└── reset-lab.sh         ← Xóa toàn bộ VMs sạch sẽ
```

**`k8s-cloud-init.yaml`** — tự động hóa hoàn toàn nhờ `dpkg --print-architecture`:
- Tắt swap, load kernel modules (`overlay`, `br_netfilter`)
- Cài `containerd` + `kubelet`, `kubeadm`, `kubectl` v1.36 phù hợp chính xác với CPU của bạn.

---

<!-- _class: lab -->

## Bước 1 — Tạo máy ảo bằng Script phù hợp

Hệ thống hỗ trợ 2 cách chạy cực kỳ linh hoạt:

**Cách 1: Chạy Router tự động (Khuyên dùng)**
```bash
cd tap-00-setup-lab/
./setup-lab.sh       # Tự phát hiện CPU & gọi script tối ưu
```

**Cách 2: Chạy trực tiếp tùy theo chip của máy bạn**
```bash
./setup-lab-arm.sh   # Nếu dùng máy Mac M1/M2/M3/M4 (ARM)
# HOẶC
./setup-lab-amd.sh   # Nếu dùng Windows/Linux hoặc Mac Intel (AMD/Intel)
```

---

## Bước 2 — Khởi tạo Control Plane

Truy cập vào controlplane và chạy lệnh khởi tạo:

```bash
# Shell vào node controlplane
multipass shell controlplane

# Khởi tạo K8s
sudo kubeadm init --apiserver-advertise-address=<IP_CỦA_CONTROLPLANE> --pod-network-cidr=10.244.0.0/16

# Copy cấu hình kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes
# NAME           STATUS     ROLES           AGE   VERSION
# controlplane   NotReady   control-plane   3m    v1.36.x
```

> **NotReady** là đúng — cluster chưa có CNI. Cài CNI theo tập học, nodes sẽ chuyển `Ready`.

---

## Bước 3 — Join Worker Nodes vào Cụm

Chạy lệnh `kubeadm join` (được in ra ở cuối Bước 2) trên các worker:

```bash
# Trên Worker 1
multipass shell worker1
sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 \
  --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# Trên Worker 2
multipass shell worker2
sudo kubeadm join <IP_CỦA_CONTROLPLANE>:6443 \
  --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

> Quay lại controlplane chạy `kubectl get nodes` sẽ thấy 3 nodes (NotReady).

---

## Bước 4 — Cài CNI theo tập học

```bash
# Flannel — đơn giản, VXLAN overlay (Tập 6-10)
kubectl apply -f \
  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Calico — BGP, Network Policy (Tập 9-26)
curl -s https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml | \
  sed "s|192.168.0.0/16|10.244.0.0/16|g" | kubectl apply -f -

# Cilium — eBPF, Hubble observability (Tập 23-43)
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true
```

```bash
# Sau khi cài CNI → nodes chuyển Ready
kubectl get nodes
# NAME           STATUS   ROLES           AGE   VERSION
# controlplane   Ready    control-plane   5m    v1.36.x
# worker1        Ready    <none>          3m    v1.36.x
# worker2        Ready    <none>          3m    v1.36.x
```

---

## Làm việc hàng ngày với lab

```bash
# Xem trạng thái cluster
kubectl get nodes -o wide
kubectl get pods -A

# Shell vào node
multipass shell controlplane
multipass shell worker1

# Ví dụ: chạy lệnh sau khi đã vào node
crictl pods
ip route show

# Thông tin IP các node
multipass list
# controlplane   Running  192.168.64.10
# worker1        Running  192.168.64.11
# worker2        Running  192.168.64.12
```

---

## Đổi CNI giữa các module

```bash
# Xóa toàn bộ VMs
./reset-lab.sh

# Khởi tạo lại VMs mới (rất nhanh vì image Ubuntu đã được cache)
./setup-lab.sh

# Sau đó thực hiện lại Bước 2 (kubeadm init/join)
# Rồi tiến hành cài CNI mới
kubectl apply -f <CNI-manifest>
```

---

<!-- _class: warn -->

## Troubleshooting

```bash
# Truy cập shell của node (ví dụ controlplane)
multipass shell controlplane

# Kiểm tra cloud-init còn chạy không
cloud-init status
# status: running  → chờ thêm
# status: done     → OK
# status: error    → xem log bên dưới

# Xem log cloud-init
sudo tail -50 /var/log/cloud-init-output.log

# containerd không chạy
systemctl status containerd
sudo systemctl restart containerd

# Nếu lỗi sai sót quá nặng → reset làm lại
./reset-lab.sh
```

---

## Xóa lab và tạo lại

```bash
# Xóa toàn bộ VMs
./reset-lab.sh

# Tạo lại từ đầu (nhanh hơn lần đầu vì Ubuntu image đã cached)
./setup-lab.sh
```

> Cloud-init image `26.04` được Multipass cache sau lần tải đầu tiên — recreate cluster chỉ mất ~2 phút thay vì 5 phút.

---


# Cluster sẵn sàng

Một cluster · dùng cho toàn bộ 45 tập · đổi CNI bằng `reset-lab.sh`

```bash

./setup-lab.sh      ← chạy một lần duy nhất
kubectl get nodes   ← kiểm tra

```
