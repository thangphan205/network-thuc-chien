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
  .hljs-bullet, .hljs-symbol { color: #fcd34d; }
  .hljs-params, .hljs-subst { color: #ffffff; }
  .hljs-deletion { color: #fca5a5; }
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

# 🚀 Lộ trình Thực chiến
## Kubernetes Networking

**Network Thực Chiến** · Kiến trúc mạng, Data Plane, Linux Kernel, eBPF & CNI

---

## 🎯 Mục tiêu Khóa học

Khóa học này **bỏ qua các khái niệm cơ bản**, đi thẳng vào bản chất của mạng Kubernetes:

1. **Linux Kernel:** Hiểu namespaces, veth pairs, iptables, eBPF.
2. **CNI Deep Dive:** Giải phẫu cấu trúc và hoạt động của Flannel, Calico, Cilium.
3. **Môi trường Lab Chuẩn:** KHÔNG dùng `kind` hay `minikube`. Sử dụng **Full VMs** (Vagrant / Multipass) để quan sát rõ nhất luồng packet thực tế.
4. **Thực chiến Day-2:** Debug, Troubleshooting, Benchmarking và Capstone Project.

---

## ✅ Điều kiện tiên quyết

Khóa học này **không dạy lại từ đầu**. Để theo kịp, bạn cần đã hoàn thành:

| # | Series | Link |
| :---: | :--- | :--- |
| 1 | **Linux Networking** — namespaces, veth, bridge, iptables, routing | [Xem playlist →](https://www.youtube.com/playlist?list=PL-3AGuUf6HCrrAi9DE8sc3oa6nidQ_Ozel) |
| 2 | **Container Networking** — network stack của Docker/containerd, CNI cơ bản | [Xem playlist →](https://www.youtube.com/playlist?list=PL-3AGuUf6HCr1WP2tHCJMgNGuPPrmocRg) |
| 3 | **Debug Mạng** — tcpdump, ss, netstat, conntrack, bắt bệnh thực tế | [Xem playlist →](https://www.youtube.com/playlist?list=PL-3AGuUf6HCoA9F33thf4aGNoJpVTUE9I) |
| 4 | **Kubernetes cơ bản (Viet Tran)** — Pod, Deployment, Service, kubectl workflow | [Xem playlist →](https://www.youtube.com/watch?v=v5wZlQnHU3A&list=PL4NoNM0L1m71ZwmAVzYX215By49z5F7MG) |

> Chưa xem? Hoàn thành các series trên trước. Kubernetes Networking **bắt đầu từ nơi các series đó dừng lại**.

---

## 📋 Tổng quan Lộ trình

| Module | Chủ đề | Số tập |
| :--- | :--- | :---: |
| **Module 0** | 🛠️ Setup Home Lab | Tập 0 |
| **Module 1** | 🔵 Nền tảng K8s Networking | Tập 1–6 |
| **Module 2** | 🟣 Giải mã Bộ 3 CNI | Tập 7–11 |
| **Module 3** | 🟠 Vận hành Thực chiến & Capstone | Tập 12–15 |

> Tổng cộng **16 tập** — từ nền tảng Linux Kernel đến ClusterMesh production-ready.

---

## 🖥️ Môi trường Lab xuyên suốt khóa học

**Cụm 3 Nodes — kubeadm trên Full VM (Multipass):**

```
┌─────────────────────────────────────────────────────┐
│  Máy tính cá nhân (Windows / Linux / macOS)         │
│  ┌─────────────────┐  ┌────────────┐  ┌──────────┐  │
│  │  controlplane   │  │  worker1   │  │ worker2  │  │
│  │  2 CPU · 2GB    │  │ 2CPU · 2GB │  │2CPU · 2GB│  │
│  └─────────────────┘  └────────────┘  └──────────┘  │
│               Multipass (HyperKit / QEMU / Hyper-V) │
└─────────────────────────────────────────────────────┘
```

| Thông số | Giá trị |
| :--- | :--- |
| **Hypervisor** | **Multipass** — dùng được trên Windows, Linux, macOS (kể cả Apple Silicon) |
| **OS** | Ubuntu 26.04 LTS |
| **Kubernetes** | v1.36 (kubeadm) |
| **Container Runtime** | containerd |
| **Pod CIDR** | `10.244.0.0/16` |
| **CNI** | Thay đổi theo module: `none` → Flannel → Calico → Cilium |

> Vagrant + VirtualBox vẫn là lựa chọn thay thế cho Windows/Linux Intel nếu Multipass gặp vấn đề.

---

<!-- _class: divider -->

# 🟢 Chủ đề 0
## Khởi động & Môi trường Lab

---

## Tập 0: Setup Home Lab Chuẩn Chuyên Gia

- **Tại sao lại dùng Full-VM?**
  - Network Engineer cần toàn quyền thao tác với interface mạng, bảng routing, bắt gói tin bằng `tcpdump` ở cấp độ Host.
  - Sử dụng **Vagrant + VirtualBox** (Windows/Linux) hoặc **Multipass** (macOS).

- **Lab thực tế:**
  - Triển khai cụm Kubernetes 3 nodes bằng `kubeadm`.
  - **Đặc biệt:** Cố tình KHÔNG cài CNI plugin để phân tích trạng thái `NotReady`.
  - Làm quen với vũ khí tối thượng: `nicolaka/netshoot`.

---

<!-- _class: divider -->

# 🔵 Chủ đề 1
## Nền tảng K8s Networking

---

## Tập 1–3: Từ Pod tới Services

- **Tập 1: Network Model & Bí mật bên trong Pod**
  - 4 nguyên tắc định tuyến của K8s. Vai trò của *Pause container* và `veth pair`.
  - Lab: Inspect network namespace của Pod bằng lệnh Linux thuần.

- **Tập 2: CNI Specification**
  - Cơ chế hoạt động của CNI v1.1.0 (`ADD`, `DEL`, `GC`, `STATUS`).
  - Lab: Tự viết cấu hình mạng thủ công bằng `cnitool`.

- **Tập 3: Kube-proxy & Bài toán Services**
  - So sánh `EndpointSlice` và `Endpoints`. Phân tích `externalTrafficPolicy`.
  - Lab: Khám phá `iptables`, `IPVS` và nâng cấp lên `nftables`.

---

## Tập 4–6: DNS, Ingress và Bảo mật

- **Tập 4: DNS trong Kubernetes & Thuế "ndots"**
  - Cơ chế CoreDNS, Headless Service. Giải quyết bài toán hiệu năng "ndots: 5".
  - Lab: Triển khai NodeLocal DNSCache.

- **Tập 5: Cuộc chuyển giao Ingress và Gateway API**
  - `ingress-nginx` đã archived (24/3/2026). Kiến trúc Gateway API v1.5 thay thế hoàn toàn.
  - Lab: Migrate từ Ingress cũ sang `HTTPRoute`.

- **Tập 6: Bảo mật với NetworkPolicy**
  - Bản chất Default-deny. Áp dụng AdminNetworkPolicy.
  - Lab: Xử lý lỗi drop traffic DNS kinh điển.

---

<!-- _class: divider -->

# 🟣 Chủ đề 2
## Giải mã Bộ 3 CNI Đình Đám

---

## Tập 7–9: Flannel & Calico

- **Tập 7: Flannel Deep Dive**
  - Đóng gói mạng Overlay. Bắt gói tin VXLAN bằng `tcpdump`.
  - Chuyển mode sang Direct Routing (`host-gw`) để tối ưu độ trễ.

- **Tập 8–9: Quyền lực của Calico**
  - Giải phẫu Felix, BIRD, Typha. Thuật toán cấp phát IP block.
  - Khi nào dùng Native BGP thay vì encapsulation.
  - Lab: Chuyển đổi Dataplane từ `iptables` sang `eBPF` trực tiếp (Zero downtime).

---

## Tập 10–11: Kỷ nguyên Cilium & eBPF

- **Tập 10: Sức mạnh eBPF & Identity Security**
  - Các hook point của eBPF (tc, XDP). Bảo mật dựa trên Identity ID (không phải IP).
  - Lab: Trực quan hóa luồng mạng với Hubble. Chặn HTTP POST ở Layer 7.

- **Tập 11: Kube-proxy Replacement & ClusterMesh**
  - Thay thế hoàn toàn Kube-proxy bằng Socket Load Balancing.
  - Lab: Kết nối 2 cụm K8s độc lập lại với nhau thông qua Cilium ClusterMesh.

---

<!-- _class: divider -->

# 🟠 Chủ đề 3
## Vận hành Thực chiến (Day 2) & Capstone

---

## Tập 12–14: Troubleshooting & Benchmarking

- **Tập 12: Observability & Bắt bệnh mạng lưới**
  - Kỹ năng dùng `kubectl debug` và `conntrack`.
  - Theo dõi luồng syscall eBPF với Inspektor Gadget / Wireshark extcap.

- **Tập 13: CNI Performance & Benchmarking**
  - Đánh giá Overhead VXLAN vs IPIP.
  - Dùng `iperf3` test throughput. Xử lý "kẻ thù giấu mặt": MTU mismatch.

- **Tập 14: K8s Networking trên Cloud**
  - So sánh AWS VPC CNI, GKE Dataplane V2, Azure CNI.
  - Khi nào dùng WireGuard vs IPsec.

---

## Tập 15: Capstone Project (Trận chiến cuối)

> **"Không gì chứng minh kỹ năng tốt hơn việc tự tay xây dựng từ đầu!"**

**Thử thách hạng nặng:**
1. Cài đặt Calico thủ công hoàn toàn từ đầu trên 3 VMs — *Calico the Hard Way*.
2. Migrate cluster đang chạy Calico sang Cilium — **Zero downtime**.
3. Dựng thêm cluster thứ 2 và thiết lập ClusterMesh.
4. Báo cáo thực chứng có đầy đủ bằng chứng.

---

<!-- _class: title -->

# Sẵn sàng chưa? 🚀

## Bắt đầu với Tập 0: Setup Home Lab

**Network Thực Chiến** · Hãy học đúng cách — deep, hands-on, và không có phím tắt.
