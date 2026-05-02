---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', 'Noto Sans', sans-serif;
    font-size: 22px;
    background: #326ce5;
    color: #ffffff;
  }
  h1 { color: #ffd700 !important; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #ffffff; font-size: 1.4em; border-bottom: 2px solid #ffd700; padding-bottom: 0.2em; }
  h3 { color: #e0e7ff; font-size: 1.1em; }
  strong { color: #fbbf24; }
  code { background: #1e3a8a; color: #86efac; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1e3a8a; border-left: 4px solid #ffd700; padding: 16px; border-radius: 6px; }
  pre code { color: #86efac; background: transparent; padding: 0; }
  .hljs-keyword, .hljs-selector-tag { color: #ff79c6; }
  .hljs-string, .hljs-addition { color: #f1fa8c; }
  .hljs-attr, .hljs-attribute { color: #93c5fd; }
  .hljs-number, .hljs-literal { color: #c4b5fd; }
  .hljs-comment { color: #93c5fd; font-style: italic; }
  .hljs-variable, .hljs-template-variable { color: #fcd34d; }
  .hljs-built_in, .hljs-name, .hljs-type { color: #86efac; }
  .hljs-meta { color: #fca5a5; }
  .hljs-title, .hljs-section { color: #bfdbfe; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  th { background: #1e3a8a; color: #ffd700; padding: 10px 14px; font-weight: 600; letter-spacing: 0.03em; }
  td { padding: 8px 14px; border-bottom: 1px solid #3b82f6; color: #ffffff; background: #2563eb; }
  tr:nth-child(even) td { background: #1d4ed8; }
  tr:hover td { background: #1e40af; }
  blockquote { border-left: 4px solid #ffd700; padding-left: 16px; color: #e0e7ff; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  section.title {
    background: linear-gradient(135deg, #1d4ed8 0%, #1e3a8a 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
    padding: 60px 80px;
  }
  section.title h1 { font-size: 2.8em; color: #ffd700 !important; border: none; }
  section.title h2 { font-size: 1.3em; color: #ffffff; border: none; margin-top: 0.2em; }
  section.title p { color: #bfdbfe; font-size: 0.9em; margin-top: 16px; }
  section.divider {
    background: linear-gradient(135deg, #1e3a8a 0%, #1d4ed8 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    text-align: center;
  }
  section.divider h1 { font-size: 2.5em; border: none; color: #ffd700 !important; }
  section.divider h2 { border: none; color: #ffffff; }
  .good { color: #86efac; font-weight: bold; }
  .bad  { color: #fca5a5; font-weight: bold; }
  .warn { color: #fcd34d; font-weight: bold; }
---
<!-- _class: title -->

# 🛠️ Tập 0: Setup Home Lab Chuẩn Chuyên Gia
## Lý thuyết: Chọn đúng vũ khí trước khi xuất trận

**Network Thực Chiến** · Series: Kubernetes Networking · Tập 00


---

# Câu hỏi đặt ra

> *"Mình là Network Engineer, mình chỉ cần cài Minikube hoặc kind lên máy là học K8s Networking được rồi, đúng không?"*

**Câu trả lời: KHÔNG.**

Và trong tập này, chúng ta sẽ tìm hiểu tại sao.


---

# 🔬 Mục tiêu của một Network Engineer khi học K8s

Kỹ sư lập trình chỉ cần Kubernetes **chạy** ứng dụng.

Network Engineer cần Kubernetes để **hiểu sâu về mạng**:
- Quan sát interface ảo `veth` được tạo ra như thế nào.
- Bắt gói tin thực tế bằng `tcpdump` trên card mạng vật lý của Node.
- Xem bảng `iptables` / `nftables` / `eBPF maps` thay đổi ra sao.
- Can thiệp trực tiếp vào `network namespace` của Pod từ OS Host.


---

# kind là gì? Tại sao nó không phù hợp?

**kind** = **K**ubernetes **IN** **D**ocker

```
┌──────────── Máy tính của bạn ────────────────┐
│  Docker Engine (Container Runtime)           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│  │ k8s-cp   │ │ worker-1 │ │ worker-2 │     │
│  │(Container)│ │(Container)│ │(Container)│   │
│  └──────────┘ └──────────┘ └──────────┘     │
└──────────────────────────────────────────────┘
```

Mỗi "Node" của kind thực chất là một **Container**, không phải một máy ảo thực sự. Chúng **chia sẻ cùng một Linux Kernel** với máy host!


---

# ❌ Điểm mù của kind và minikube

| Thao tác | kind / minikube | Full VM |
| :--- | :---: | :---: |
| Chạy ứng dụng đơn giản | ✅ | ✅ |
| Dùng `tcpdump` trên card mạng vật lý của Node | ❌ | ✅ |
| Can thiệp `ip route`, `ip link` ở mức OS của Node | ❌ | ✅ |
| Quan sát interface VXLAN (`flannel.1`, `vxlan.calico`) | ❌ | ✅ |
| Test kernel module (ipvs, nf_conntrack) | ❌ | ✅ |
| Giả lập môi trường Production thực tế | ❌ | ✅ |


---

# ✅ Full VM - Toàn quyền kiểm soát

```
┌──────────── Máy tính của bạn ────────────────┐
│  Hypervisor (VirtualBox / Hyper-V / HyperKit)│
│  ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│  │ ctrl-pln │ │ worker-1 │ │ worker-2 │     │
│  │ (Ubuntu) │ │ (Ubuntu) │ │ (Ubuntu) │     │
│  │Kernel cô │ │Kernel cô │ │Kernel cô │     │
│  │lập riêng │ │lập riêng │ │lập riêng │     │
│  └──────────┘ └──────────┘ └──────────┘     │
└──────────────────────────────────────────────┘
```

Mỗi Node là một **máy ảo Ubuntu thực thụ** với **Kernel riêng biệt**. Bạn có thể `ssh` vào và làm mọi thứ giống như một máy chủ vật lý.


---

# 🛠 Công cụ ảo hóa chúng ta dùng

Để khởi động 3 máy ảo tự động (không phải cài tay từng cái), ta dùng:

| Hệ điều hành | Công cụ | Hypervisor ngầm |
| :--- | :--- | :--- |
| **Windows / Linux** | **Vagrant** + VirtualBox | VirtualBox |
| **macOS (Intel)** | **Vagrant** + VirtualBox | VirtualBox |
| **macOS (Apple M-series)** | **Multipass** | HyperKit / QEMU |

> **Tại sao không dùng VirtualBox trên Mac M-series?**
> VirtualBox **không hỗ trợ** chip ARM (Apple Silicon). Multipass là giải pháp Native tối ưu của Canonical dành riêng cho dòng máy này.


---

# ⚙️ Kiến trúc K8s Control Plane

```
┌─────────────────── Control Plane Node ───────────────────┐
│  ┌──────────────┐   ┌─────────────┐   ┌────────────────┐ │
│  │  API Server  │   │  Scheduler  │   │ Ctrl Manager   │ │
│  │(Cổng vào K8s)│   │(Chọn Node   │   │(Duy trì trạng  │ │
│  │              │   │cho Pod)     │   │thái mong muốn) │ │
│  └──────┬───────┘   └─────────────┘   └────────────────┘ │
│         │                                                  │
│  ┌──────▼───────────────────────────────────────────────┐ │
│  │              etcd (Key-Value Store)                  │ │
│  │           "Não bộ" lưu trữ mọi trạng thái           │ │
│  └──────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```


---

# ⚙️ Kiến trúc K8s Worker Node

```
┌────────────────── Worker Node ──────────────────────────┐
│                                                          │
│   ┌───────────┐     ┌────────────┐    ┌─────────────┐   │
│   │  kubelet  │     │ kube-proxy │    │  Container  │   │
│   │(Người giám│     │(Quản lý    │    │  Runtime    │   │
│   │sát Pod)   │     │iptables/   │    │(containerd) │   │
│   └─────┬─────┘     │IPVS rules) │    └─────────────┘   │
│         │           └────────────┘                       │
│   ┌─────▼──────────────────────────────────────────┐    │
│   │            CNI Plugin (Flannel/Calico/Cilium)   │    │
│   │       "Người cấp phát IP và kết nối mạng Pod"  │    │
│   └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```


---

# 🧩 Luồng hoạt động khi tạo một Pod

```
kubectl apply -f pod.yaml
        │
        ▼
  [1] API Server nhận yêu cầu và lưu vào etcd
        │
        ▼
  [2] Scheduler chọn Worker Node phù hợp
        │
        ▼
  [3] kubelet trên Worker Node nhận lệnh tạo Pod
        │
        ▼
  [4] kubelet gọi Container Runtime (containerd) tạo container
        │
        ▼
  [5] kubelet gọi CNI Plugin để CẤP PHÁT IP và KẾT NỐI MẠNG
        │
        ▼
  [6] Pod đã chạy và có IP! ✅
```


---

# ❓ Nếu không có CNI thì sao?

Đây chính là **thí nghiệm đầu tiên** chúng ta sẽ làm trong bài Lab!

Sau khi `kubeadm init`, chúng ta **cố tình KHÔNG cài CNI** và quan sát:

```bash
$ kubectl get nodes
NAME           STATUS     ROLES           AGE
controlplane   NotReady   control-plane   2m  # ← NotReady!
worker1        NotReady   <none>          1m  # ← NotReady!
worker2        NotReady   <none>          1m  # ← NotReady!

$ kubectl get pods -n kube-system
NAME                    READY   STATUS    RESTARTS
coredns-xxx             0/1     Pending   0        # ← Pending!
```

> Thiếu CNI = Không có mạng = Node `NotReady` = CoreDNS `Pending`.


---

# 🎯 Tóm lại

- **kind / minikube:** Tuyệt vời để dev ứng dụng nhanh. **Không phù hợp** để học sâu về networking.
- **Full VM (Vagrant / Multipass):** Môi trường **giống Production thực tế nhất** trên máy tính cá nhân. Toàn quyền can thiệp kernel.
- **K8s Control Plane** gồm: API Server, Scheduler, Controller Manager, etcd.
- **Worker Node** gồm: kubelet, kube-proxy, Container Runtime, và **CNI Plugin** (điều chúng ta sẽ mổ xẻ xuyên suốt khóa học).


---

# 👉 Bước tiếp theo: Bài Lab

Mở thư mục `lab-module0/` và làm theo hướng dẫn phù hợp với hệ điều hành của bạn:
- **Vagrant (Windows/Linux/macOS Intel):** `lab-module0-guide.md`
- **Multipass (macOS Apple Silicon):** `lab-module0-macos-guide.md`
