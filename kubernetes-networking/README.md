# 🚀 Lộ trình Thực chiến Kubernetes Networking (Course Tracker)

Chào mừng bạn đến với lộ trình học **Kubernetes Networking** chuyên sâu! Khóa học này bỏ qua các khái niệm cơ bản để đi thẳng vào kiến trúc mạng, Data Plane và cách K8s thao tác với Linux kernel (namespaces, veth pairs, iptables, eBPF).

Tài liệu này được thiết kế dưới dạng checklist để bạn dễ dàng theo dõi tiến độ học tập kết hợp cùng với series video trên YouTube. Hãy đánh dấu `[x]` vào các tập bạn đã hoàn thành nhé!

---

## 🛠 Môi trường Lab Thực chiến

Để thấy rõ cách Linux kernel xử lý gói tin (bắt gói tin bằng `tcpdump`, xem interface ảo `veth`, kiểm tra bảng routing), khóa học này **KHÔNG** sử dụng `kind`, `minikube` hay `Docker Desktop`. 

Thay vào đó, chúng ta sử dụng **Máy ảo hoàn chỉnh (Full VMs)** với 2 giải pháp ảo hóa tốc độ cao:
- **Windows / Linux:** Dùng **Vagrant + VirtualBox**.
- **macOS (Đặc biệt là Apple Silicon M-series):** Dùng **Multipass**.

*(👉 Xem chi tiết hướng dẫn tự động hóa việc tạo lab trong thư mục `lab-module0/`)*

---

## 🟢 Chủ đề 0: Khởi động & Chuẩn bị Vũ khí (Tương đương Module 0)

- [ ] **Tập 0: Setup Home Lab Chuẩn Chuyên Gia**
  - **Lý thuyết:** Tại sao Network Engineer cần Full-VM (Vagrant/Multipass) thay vì dùng `kind` hay `minikube`? Kiến trúc K8s Control Plane.
  - **Lab:** Triển khai cluster 3 nodes bằng `kubeadm`. **Cố tình KHÔNG cài CNI plugin** để quan sát trạng thái `NotReady` của các Node và hiểu vai trò cốt lõi của CNI. Làm quen với công cụ debug mạng thần thánh `nicolaka/netshoot`.

---

## 🔵 Chủ đề 1: Nền tảng K8s Networking (Tương đương Phase I)

- [ ] **Tập 1: Network Model & Bí mật bên trong Pod**
  - **Lý thuyết:** 4 nguyên tắc định tuyến không cần NAT của K8s. Pause container và veth pair hoạt động ra sao.
  - **Lab:** Dùng lệnh Linux thuần để inspect network namespace của Pod từ worker node vật lý.

- [ ] **Tập 2: CNI Specification hoạt động ra sao?**
  - **Lý thuyết:** Cơ chế CNI v1.1.0, các động từ `ADD`, `DEL`, `GC`, `STATUS` và luồng chạy của file cấu hình `.conflist`.
  - **Lab:** Tự viết cấu hình mạng (bridge -> portmap -> firewall) và kích hoạt bằng tay (thủ công) bằng lệnh `cnitool`.

- [ ] **Tập 3: Kube-proxy & Bài toán Services**
  - **Lý thuyết:** `EndpointSlice` thay thế `Endpoints` (bị loại bỏ ở K8s v1.33). Cơ chế `externalTrafficPolicy: Local` vs `Cluster`.
  - **Lab:** Phân tích packet đi qua các chain của `iptables`, xem xét cấu trúc bảng IPVS, và nâng cấp lên `nftables` mode (GA ở v1.33).

- [ ] **Tập 4: DNS trong Kubernetes & Thuế "ndots"**
  - **Lý thuyết:** Cách CoreDNS phân giải tên miền nội bộ, nguyên lý Headless Service, và bài toán rò rỉ hiệu năng do "thuế ndots: 5".
  - **Lab:** Bắt log số lượng query DNS bằng netshoot, triển khai NodeLocal DNSCache tại IP tĩnh `169.254.20.10`.

- [ ] **Tập 5: Cuộc chuyển giao Ingress và Gateway API**
  - **Lý thuyết:** Lý do `ingress-nginx` nghỉ hưu (dự kiến tháng 3/2026) và kiến trúc Role-oriented tiên tiến của Gateway API v1.4.
  - **Lab:** Cấu hình routing bằng Ingress API cũ, xem file `nginx.conf` được sinh ra, sau đó migrate sang `HTTPRoute` của Gateway API.

- [ ] **Tập 6: Bảo mật với NetworkPolicy**
  - **Lý thuyết:** Bản chất Default-deny trong K8s. Sự khác biệt giữa NetworkPolicy truyền thống và AdminNetworkPolicy (Allow, Deny, Pass).
  - **Lab:** Áp dụng policy, phát hiện lỗi drop traffic DNS (lỗi kinh điển số 1 khi mới viết policy), và thử nghiệm trên các CNI khác nhau.

---

## 🟣 Chủ đề 2: Giải mã Bộ 3 CNI Đình Đám (Tương đương Phase II)

- [ ] **Tập 7: Flannel Deep Dive - Đơn giản nhưng mạnh mẽ**
  - **Lý thuyết:** Đóng gói mạng (Overlay Network). Luồng packet qua VXLAN (cổng UDP 8472) và kỹ thuật Direct Routing (host-gw).
  - **Lab:** Dùng `tcpdump` soi chi tiết header của packet VXLAN, kiểm tra bảng FDB/ARP trên Linux, và chuyển đổi cụm sang mode `host-gw` để giảm độ trễ (overhead).

- [ ] **Tập 8: Calico (Phần 1) - Kiến trúc và IPAM**
  - **Lý thuyết:** Giải phẫu các thành phần Felix, BIRD, Typha. Cơ chế IPPool (chia subnet `/26` mặc định).
  - **Lab:** Cài đặt Calico qua Tigera Operator, kiểm tra thuật toán cấp phát IP block và soi giao diện `tunl0` / `vxlan.calico`.

- [ ] **Tập 9: Calico (Phần 2) - Native BGP & eBPF Dataplane**
  - **Lý thuyết:** Khi nào dùng BGP thuần (không encapsulation) thay vì IPIP/VXLAN trên môi trường Cloud/On-premise.
  - **Lab:** Chuyển đổi qua lại (toggle) giữa iptables dataplane và eBPF dataplane trực tiếp trên cụm đang chạy mà không gây downtime.

- [ ] **Tập 10: Cilium (Phần 1) - Sức mạnh eBPF & Identity Security**
  - **Lý thuyết:** Các điểm hook của eBPF trong Kernel (tc, XDP, cgroup socket). Cơ chế bảo mật dựa trên Identity ID thay vì phụ thuộc vào địa chỉ IP.
  - **Lab:** Cài đặt Cilium CLI, dùng lệnh `hubble observe` để trực quan hóa luồng mạng, thiết lập `CiliumNetworkPolicy` để chặn API HTTP POST ở tận Layer 7.

- [ ] **Tập 11: Cilium (Phần 2) - Kube-proxy Replacement & Multi-cluster**
  - **Lý thuyết:** Socket Load Balancing hoạt động ra sao để "đá bay" hoàn toàn iptables DNAT của Kube-proxy.
  - **Lab:** Xóa bỏ hoàn toàn Kube-proxy trên cluster, sau đó kết nối 2 cụm Kubernetes độc lập lại với nhau bằng Cilium ClusterMesh.

---

## 🟠 Chủ đề 3: Vận hành Thực chiến (Day 2 Operations) & Capstone (Tương đương Phase III)

- [ ] **Tập 12: Observability & Troubleshooting (Bắt bệnh mạng lưới)**
  - **Lý thuyết & Lab:** Kỹ năng sinh tồn: Sử dụng `kubectl debug` đính kèm netshoot vào Pod đang lỗi. Dùng `conntrack` xử lý sự cố nghẽn kết nối, theo dõi luồng syscall eBPF với Inspektor Gadget và Wireshark extcap (ra mắt cuối 2025).

- [ ] **Tập 13: CNI Performance & Benchmarking**
  - **Lý thuyết & Lab:** Tính toán Overhead kích thước gói tin của VXLAN vs IPIP. Demo dùng `iperf3` test throughput & độ trễ giữa các node. Thử nghiệm tự tạo lỗi để giải quyết "kẻ thù giấu mặt": MTU mismatch.

- [ ] **Tập 14: K8s Networking trên Cloud & Tiêu chuẩn chọn CNI**
  - **Lý thuyết:** Tìm hiểu mặc định của các gã khổng lồ: AWS VPC CNI, GKE Dataplane V2 (Cilium), AKS Azure CNI Powered by Cilium. Khi nào nên dùng mã hóa WireGuard so với IPsec cho traffic nội bộ.

- [ ] **Tập 15: Capstone Project (Trận chiến cuối cùng)**
  - **Lab hạng nặng:** Triển khai Calico thủ công hoàn toàn từ đầu trên 3 VMs (Calico the Hard Way), migrate một cluster đang dùng Calico sang Cilium chuẩn bài, thêm cụm thứ 2 để dựng ClusterMesh và xuất báo cáo thực chứng.