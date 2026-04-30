---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', 'Noto Sans', sans-serif;
    font-size: 22px;
    background: #0f1117;
    color: #e2e8f0;
  }
  h1 { color: #63b3ed; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #68d391; font-size: 1.4em; border-bottom: 2px solid #68d391; padding-bottom: 0.2em; }
  h3 { color: #f6ad55; font-size: 1.1em; }
  code { background: #1e2130; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1e2130; border-left: 4px solid #63b3ed; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  .hljs-keyword, .hljs-selector-tag { color: #ff79c6; }
  .hljs-string, .hljs-addition { color: #f1fa8c; }
  .hljs-attr, .hljs-attribute { color: #79b8ff; }
  .hljs-number, .hljs-literal { color: #bd93f9; }
  .hljs-comment { color: #6272a4; font-style: italic; }
  .hljs-variable, .hljs-template-variable { color: #ffb86c; }
  .hljs-built_in, .hljs-name, .hljs-type { color: #50fa7b; }
  .hljs-meta { color: #ff5555; }
  .hljs-title, .hljs-section { color: #8be9fd; }
  .hljs-bullet, .hljs-symbol { color: #ffb86c; }
  .hljs-params, .hljs-subst { color: #e2e8f0; }
  .hljs-deletion { color: #ff5555; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  th { background: #1e4976; color: #e2f0ff; padding: 10px 14px; font-weight: 600; letter-spacing: 0.03em; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a3550; color: #e2e8f0; background: #1a2035; }
  tr:nth-child(even) td { background: #232d47; }
  tr:hover td { background: #2a3a5c; }
  blockquote { border-left: 4px solid #f6ad55; padding-left: 16px; color: #b0bcd0; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  section.title {
    background: linear-gradient(135deg, #0f1117 0%, #1a2040 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
    padding: 60px 80px;
  }
  section.title h1 { font-size: 2.8em; color: #63b3ed; border: none; }
  section.title h2 { font-size: 1.3em; color: #68d391; border: none; margin-top: 0.2em; }
  section.title p { color: #a0aec0; font-size: 0.9em; margin-top: 16px; }
  section.divider {
    background: linear-gradient(135deg, #1a2040 0%, #0f1117 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    text-align: center;
  }
  section.divider h1 { font-size: 2.5em; border: none; }
  section.divider h2 { border: none; }
  .highlight { color: #ffb86c; font-weight: bold; }
---

<!-- _class: title -->

# 🚀 Lộ trình Thực chiến
## Kubernetes Networking

**Khóa học chuyên sâu:** Kiến trúc mạng, Data Plane, Linux Kernel, eBPF & CNI

---

## 🎯 Mục tiêu Khóa học

Khóa học này **bỏ qua các khái niệm cơ bản**, đi thẳng vào bản chất của mạng Kubernetes:

1. **Linux Kernel:** Hiểu namespaces, veth pairs, iptables, eBPF.
2. **CNI Deep Dive:** Giải phẫu cấu trúc và hoạt động của Flannel, Calico, Cilium.
3. **Môi trường Lab Chuẩn:** KHÔNG dùng `kind` hay `minikube`. Sử dụng **Full VMs** (Vagrant / Multipass) để quan sát rõ nhất luồng packet thực tế.
4. **Thực chiến Day-2:** Debug, Troubleshooting, Benchmarking và Capstone Project.

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

## Tập 1-3: Từ Pod tới Services

- **Tập 1: Network Model & Bí mật bên trong Pod**
  - 4 nguyên tắc định tuyến của K8s. Vai trò của *Pause container* và `veth pair`.
  - Lab: Inspect network namespace của Pod bằng lệnh Linux thuần.

- **Tập 2: CNI Specification**
  - Cơ chế hoạt động của CNI v1.1.0 (`ADD`, `DEL`).
  - Lab: Tự viết cấu hình mạng thủ công bằng `cnitool`.

- **Tập 3: Kube-proxy & Bài toán Services**
  - So sánh `EndpointSlice` và `Endpoints`. Phân tích `externalTrafficPolicy`.
  - Lab: Khám phá `iptables`, `IPVS` và nâng cấp lên `nftables`.

---

## Tập 4-6: DNS, Ingress và Bảo mật

- **Tập 4: DNS trong Kubernetes & Thuế "ndots"**
  - Cơ chế CoreDNS, Headless Service. Giải quyết bài toán hiệu năng "ndots: 5".
  - Lab: Triển khai NodeLocal DNSCache.

- **Tập 5: Cuộc chuyển giao Ingress và Gateway API**
  - Kiến trúc Gateway API v1.4 thay thế `ingress-nginx`.
  - Lab: Migrate từ Ingress cũ sang `HTTPRoute`.

- **Tập 6: Bảo mật với NetworkPolicy**
  - Bản chất Default-deny. Áp dụng AdminNetworkPolicy.
  - Lab: Xử lý lỗi drop traffic DNS kinh điển.

---

<!-- _class: divider -->

# 🟣 Chủ đề 2
## Giải mã Bộ 3 CNI Đình Đám

---

## Tập 7-9: Flannel & Calico

- **Tập 7: Flannel Deep Dive**
  - Đóng gói mạng Overlay. Bắt gói tin VXLAN bằng `tcpdump`.
  - Chuyển mode sang Direct Routing (`host-gw`) để tối ưu độ trễ.

- **Tập 8-9: Quyền lực của Calico**
  - Giải phẫu Felix, BIRD, Typha. Thuật toán cấp phát IP block.
  - Khi nào dùng Native BGP thay vì encapsulation.
  - Lab: Chuyển đổi Dataplane từ `iptables` sang `eBPF` trực tiếp (Zero downtime).

---

## Tập 10-11: Kỷ nguyên Cilium & eBPF

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

## Tập 12-14: Troubleshooting & Benchmarking

- **Tập 12: Observability & Bắt bệnh mạng lưới**
  - Kỹ năng dùng `kubectl debug` và `conntrack`. 
  - Theo dõi luồng syscall eBPF với Inspektor Gadget / Wireshark extcap.

- **Tập 13: CNI Performance & Benchmarking**
  - Đánh giá Overhead VXLAN vs IPIP.
  - Dùng `iperf3` test throughput. Xử lý "kẻ thù giấu mặt": MTU mismatch.

- **Tập 14: K8s Networking trên Cloud**
  - So sánh AWS VPC CNI, GKE Dataplane V2, Azure CNI. Khi nào dùng WireGuard vs IPsec.

---

## Tập 15: Capstone Project (Trận chiến cuối)

> **"Không gì chứng minh kỹ năng tốt hơn việc tự tay xây dựng từ đầu!"**

**Thử thách hạng nặng:**
1. Cài đặt Calico thủ công hoàn toàn từ đầu trên 3 VMs (Calico the Hard Way).
2. Migrate một cluster đang chạy Calico sang Cilium chuẩn bài.
3. Dựng thêm cluster thứ 2 và thiết lập ClusterMesh.
4. Báo cáo thực chứng.

---

<!-- _class: title -->

# Sẵn sàng chưa? 🚀

Hãy bắt đầu với **Tập 0: Setup Home Lab** ngay hôm nay!
