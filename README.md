# 🌐 Network Thực Chiến — Tài liệu Lab & Slide

> **Kho tài liệu thực hành đồng hành cùng kênh YouTube [Network Thực Chiến](https://www.youtube.com/@NetworkThucChien)** 🚀
> 
> Nội dung được xây dựng theo triết lý **"Học bằng cách thực hành" (Hands-on Learning)** — Bỏ qua lý thuyết suông, đi thẳng vào bản chất thông qua các bài lab thực tế được dựng hoàn toàn trên máy tính cá nhân.

---

<p align="center">
  <a href="https://www.youtube.com/@NetworkThucChien">
    <img src="https://img.shields.io/badge/YouTube-Network%20Thực%20Chiến-red?style=for-the-badge&logo=youtube" alt="YouTube Channel">
  </a>
  <a href="https://github.com/thangphan205/network-thuc-chien">
    <img src="https://img.shields.io/github/stars/thangphan205/network-thuc-chien?style=for-the-badge&color=gold" alt="GitHub Stars">
  </a>
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="License">
</p>

---

## 🗺️ Bản đồ Lộ trình & Playlist YouTube

Dưới đây là sơ đồ các Module học tập cùng các playlist video đồng hành. Bạn nên kết hợp **vừa xem video giải thích lý thuyết/bản chất, vừa thực hành lab** trong repo này để đạt hiệu quả cao nhất.

| Module học tập | Thư mục mã nguồn | Playlist YouTube đồng hành 📺 | Mô tả |
| :--- | :--- | :--- | :--- |
| ☸️ **Kubernetes Networking** | [`kubernetes-networking/`](./kubernetes-networking) | [Xem Playlist K8s Networking](https://www.youtube.com/playlist?list=PL-3AGuUf6HCqpYV1BvKPtxMzxEeIKpWR2) | Series chuyên sâu 46 tập từ Linux kernel đến Production (Flannel, Calico, Cilium, eBPF) |
| 🔍 **Debug Mạng từ A-Z** | [`debug-mang-az/`](./debug-mang-az) | [Kênh Network Thực Chiến](https://www.youtube.com/@NetworkThucChien) | Kỹ năng chẩn đoán lỗi mạng có hệ thống theo tầng OSI (Ping, MTR, SS, Netcat, Curl, Tcpdump) |
| 🐳 **Container Networking** | [`container-networking/`](./container-networking) | [Kênh Network Thực Chiến](https://www.youtube.com/@NetworkThucChien) | Nền tảng Linux Networking: network namespaces, bridge, iptables, nftables, Docker networking |
| 🤖 **Network Automation** | [`network-automation/`](./network-automation) | [Kênh Network Thực Chiến](https://www.youtube.com/@NetworkThucChien) | Tự động hóa mạng với Python (Paramiko, Netmiko, Scrapli), Ansible và xây dựng API bằng FastAPI |
| 🐧 **Cumulus Linux & Routing** | [`cumulus-linux/`](./cumulus-linux) | [Xem Playlist FRRouting](https://www.youtube.com/playlist?list=PL-3AGuUf6HCrgGBtAQ8Ym3JRcMJWHxZ0j) | Định tuyến động (BGP, OSPF, VXLAN) với FRRouting trên Cumulus Linux |
| 🔬 **Wireshark Thực Chiến** | [`wireshark/`](./wireshark) | [Xem Playlist Wireshark](https://www.youtube.com/playlist?list=PL-3AGuUf6HCpLvQl_ETF-1zVM-Pu-cJ4X) | Phân tích gói tin chuyên sâu, giải mã TLS, điều tra sự cố bảo mật |
| 🛠️ **Open-source Tools** | [`opensource-tools/`](./opensource-tools) | [Kênh Network Thực Chiến](https://www.youtube.com/@NetworkThucChien) | Các công cụ tối ưu hóa công việc: Multipass, Vagrant, Containerlab... |
| 🎮 **Đố Vui Mạng** | [`do-vui/`](./do-vui) | [Kênh Network Thực Chiến](https://www.youtube.com/@NetworkThucChien) | Các thử thách mạng thú vị, CTF-style giúp rèn luyện tư duy |

---

## 🚀 Hướng dẫn Bắt đầu nhanh (Quick Start)

Dành cho người mới bắt đầu tiếp cận Repository này:

### 1. Clone repository về máy cá nhân
```bash
git clone https://github.com/thangphan205/network-thuc-chien.git
cd network-thuc-chien
```

### 2. Chuẩn bị môi trường Lab
Phần lớn các bài lab ở đây sử dụng máy ảo Linux (VM) hoặc các container để giả lập thiết bị mạng. Bạn nên chuẩn bị sẵn:
* **Multipass** (Khuyên dùng): Để tạo nhanh các máy ảo Ubuntu sạch trên macOS/Windows/Linux. Xem hướng dẫn cài đặt tại [`opensource-tools/multipass/`](./opensource-tools/multipass).
* **Containerlab**: Sử dụng cho các bài lab Network Automation và Cumulus Linux. Xem hướng dẫn tại [`containerlab/`](./network-automation/containerlab).
* **Docker**: Cần thiết cho phần Container Networking và Kubernetes setup.

> [!TIP]
> Nếu bạn học phần **Kubernetes Networking**, hãy truy cập thư mục [`k8s-lab/tap-00-setup-lab/`](./kubernetes-networking/k8s-lab/tap-00-setup-lab) để dựng nhanh cụm Cluster 3-node chỉ bằng một dòng lệnh!

---

## ☸️ 1. Kubernetes Networking (Series 46 tập)

> **Series chuyên sâu** — Đi sâu vào kiến trúc mạng, Data Plane và cách K8s tương tác với Linux kernel (Namespaces, veth pairs, iptables, eBPF). Ba CNI chính được mổ xẻ: **Flannel → Calico → Cilium**.

* 📁 **Thư mục Lab:** [`kubernetes-networking/`](./kubernetes-networking)
* 📺 **Playlist học tập:** [Kubernetes Networking - YouTube](https://www.youtube.com/playlist?list=PL-3AGuUf6HCqpYV1BvKPtxMzxEeIKpWR2)

### Môi trường Lab Kubernetes chuyên nghiệp
Chúng ta sử dụng cụm VM chạy trên Multipass (không dùng `kind` hay `minikube`) để có toàn quyền can thiệp kernel:
* Cài đặt tự động bằng cloud-init: [k8s-node.yaml](./kubernetes-networking/k8s-lab/tap-00-setup-lab/k8s-node.yaml)
* Script tạo Cluster 3-node: [setup-lab.sh](./kubernetes-networking/k8s-lab/tap-00-setup-lab/setup-lab.sh)

```bash
cd kubernetes-networking/k8s-lab/tap-00-setup-lab
./setup-lab.sh flannel    # Dựng cluster và cài đặt Flannel CNI
./setup-lab.sh calico     # Dựng cluster và cài đặt Calico CNI
./setup-lab.sh cilium     # Dựng cluster và cài đặt Cilium CNI (eBPF)
```

### Lộ trình học tập chi tiết

<details>
<summary><b>⚪ Phần 0 — Nền tảng (Tập 1–5)</b></summary>

| Tập | Chủ đề | Tài liệu Lab |
| :---: | :--- | :--- |
| **0** | Setup Lab — Multipass + cloud-init + kubeadm | [`tap-00-setup-lab/`](./kubernetes-networking/k8s-lab/tap-00-setup-lab) |
| **1** | Kubernetes Network Model: 4 nguyên tắc không NAT | [`tap-01-kubernetes-network-model/`](./kubernetes-networking/k8s-lab/tap-01-kubernetes-network-model) |
| **2** | Pod Network: Pause Container, veth pair & Network Namespace | [`tap-02-pod-network/`](./kubernetes-networking/k8s-lab/tap-02-pod-network) |
| **3** | Services & kube-proxy: ClusterIP, NodePort, LoadBalancer từ góc nhìn packet | [`tap-03-services-kube-proxy/`](./kubernetes-networking/k8s-lab/tap-03-services-kube-proxy) |
| **4** | CoreDNS & Thuế "ndots:5": Tại sao mỗi request tốn 5 DNS query? | [`tap-04-dns/`](./kubernetes-networking/k8s-lab/tap-04-dns) |
| **5** | CNI là gì? Hành trình cắm mạng cho Pod từ ADD đến DEL | [`tap-05-cni/`](./kubernetes-networking/k8s-lab/tap-05-cni) |

</details>

<details>
<summary><b>🟡 Phần 1 — Flannel CNI (Tập 6–10)</b></summary>

| Tập | Chủ đề | Tài liệu Lab |
| :---: | :--- | :--- |
| **6** | Flannel là gì? Vấn đề Pod-to-Pod Communication | [`tap-06-flannel/`](./kubernetes-networking/k8s-lab/tap-06-flannel) |
| **7** | Kiến trúc Flannel: flanneld, etcd và CNI plugin | [`tap-07-flannel-vxlan/`](./kubernetes-networking/k8s-lab/tap-07-flannel-vxlan) |
| **8** | VXLAN Backend: Flannel đóng gói packet như thế nào? (50 bytes overhead) | [`tap-08-flannel-hostgw-security/`](./kubernetes-networking/k8s-lab/tap-08-flannel-hostgw-security) |
| **9** | host-gw Mode: Khi nào bỏ encapsulation để tăng tốc? | [`tap-08-flannel-hostgw-security/`](./kubernetes-networking/k8s-lab/tap-08-flannel-hostgw-security) |
| **10** | Giới hạn của Flannel: Tại sao không có NetworkPolicy? | [`tap-08-flannel-hostgw-security/`](./kubernetes-networking/k8s-lab/tap-08-flannel-hostgw-security) |

</details>

<details>
<summary><b>🔵 Phần 2 — Calico CNI (Tập 11–24)</b></summary>

| Tập | Chủ đề | Tài liệu Lab |
| :---: | :--- | :--- |
| **11** | Lateral Movement & Blast Radius: Bài toán bảo mật Flannel bỏ qua | [`tap-09-calico-cni/`](./kubernetes-networking/k8s-lab/tap-09-calico-cni) |
| **12** | Kiến trúc Calico: Felix, BIRD, Datastore — Ai làm gì? | [`tap-10-calico-architecture/`](./kubernetes-networking/k8s-lab/tap-10-calico-architecture) |
| **13** | iptables vs eBPF Dataplane: O(n) vs O(1) | [`tap-11-ebpf-dataplane/`](./kubernetes-networking/k8s-lab/tap-11-ebpf-dataplane) |
| **14** | veth pair & conntrack: Hành trình của 1 packet qua Calico | [`tap-12-packet-flow/`](./kubernetes-networking/k8s-lab/tap-12-packet-flow) |
| **15** | NetworkPolicy cơ bản: Default Deny và Ingress Policy | [`tap-13-networkpolicy-basics/`](./kubernetes-networking/k8s-lab/tap-13-networkpolicy-basics) |
| **16** | Cross-namespace Policy: AND vs OR — Dấu gạch "-" quan trọng thế nào! | [`tap-14-cross-namespace-policy/`](./kubernetes-networking/k8s-lab/tap-14-cross-namespace-policy) |
| **17** | Union Logic: NetworkPolicy hoạt động như Security Group, không phải ACL | [`tap-15-union-logic/`](./kubernetes-networking/k8s-lab/tap-15-union-logic) |
| **18** | BGP trong Calico: Node-to-Node Mesh và chuyển từ VXLAN | [`tap-16-bgp-calico/`](./kubernetes-networking/k8s-lab/tap-16-bgp-calico) |
| **19** | WireGuard trong Calico: Mã hóa traffic nội bộ & bẫy MTU 1440 bytes | [`tap-17-wireguard/`](./kubernetes-networking/k8s-lab/tap-17-wireguard) |
| **20** | Lab Troubleshooting 1: "Pod thiếu label" — Connection Timeout không rõ lý do | [`tap-18-lab-1/`](./kubernetes-networking/k8s-lab/tap-18-lab-1) |
| **21** | Lab Troubleshooting 2: BGP không quảng bá Pod CIDR | [`tap-19-lab-2/`](./kubernetes-networking/k8s-lab/tap-19-lab-2) |
| **22** | Lab Troubleshooting 3: Sự cố phân quyền truy cập chéo Namespace | [`tap-20-lab-3/`](./kubernetes-networking/k8s-lab/tap-20-lab-3) |
| **23** | Lab Troubleshooting 4: Network Policy Nâng Cao (GlobalNetworkPolicy, NetworkSet) | [`tap-21-lab-4/`](./kubernetes-networking/k8s-lab/tap-21-lab-4) |
| **24** | Tổng kết & Workflow Troubleshooting Calico chuẩn | [`tap-22-calico-troubleshooting/`](./kubernetes-networking/k8s-lab/tap-22-calico-troubleshooting) |

</details>

<details>
<summary><b>🟣 Phần 3 — Cilium CNI & eBPF (Tập 25–41)</b></summary>

| Tập | Chủ đề | Tài liệu Lab |
| :---: | :--- | :--- |
| **25** | Tại sao Cilium? Pain points của Calico & sockops bypass | [`tap-23-cilium-why/`](./kubernetes-networking/k8s-lab/tap-23-cilium-why) |
| **26** | BPF Maps: Hash, LRU, Array, Per-CPU — Vũ khí hiệu năng của Cilium | [`tap-24-bpf-maps/`](./kubernetes-networking/k8s-lab/tap-24-bpf-maps) |
| **27** | Kiến trúc Cilium: Operator, Agent, GoBGP, Hubble | [`tap-25-cilium-architecture/`](./kubernetes-networking/k8s-lab/tap-25-cilium-architecture) |
| **28** | 3 Hook Points của eBPF: XDP, TC và sockops | [`tap-26-ebpf-hooks/`](./kubernetes-networking/k8s-lab/tap-26-ebpf-hooks) |
| **29** | Cùng Node vs Khác Node: Tại sao sockops bypass hoàn toàn XDP/TC? | [`tap-27-same-node-vs-cross-node/`](./kubernetes-networking/k8s-lab/tap-27-same-node-vs-cross-node) |
| **30** | L3/L4 Policy trong Cilium: So sánh với Kubernetes NetworkPolicy | [`tap-28-cilium-l3l4-policy/`](./kubernetes-networking/k8s-lab/tap-28-cilium-l3l4-policy) |
| **31** | L7 Policy: Chặn HTTP POST theo path với Envoy Proxy | [`tap-29-cilium-l7-policy/`](./kubernetes-networking/k8s-lab/tap-29-cilium-l7-policy) |
| **32** | DNS Policy với toFQDNs: Filter theo domain thay vì IP | [`tap-30-fqdn-dns-policy/`](./kubernetes-networking/k8s-lab/tap-30-fqdn-dns-policy) |
| **33** | Cilium + Istio: Khi nào kết hợp, khi nào dùng Cilium thuần? | [`tap-31-cilium-vs-istio/`](./kubernetes-networking/k8s-lab/tap-31-cilium-vs-istio) |
| **34** | Hubble CLI: `hubble observe` — Debug real-time không cần SSH | [`tap-32-hubble-cli/`](./kubernetes-networking/k8s-lab/tap-32-hubble-cli) |
| **35** | Hubble UI: Service Map tự động & DROPPED màu đỏ | [`tap-33-hubble-ui/`](./kubernetes-networking/k8s-lab/tap-33-hubble-ui) |
| **36** | Hubble Metrics: hubble_drop_total, http_requests | [`tap-34-hubble-metrics/`](./kubernetes-networking/k8s-lab/tap-34-hubble-metrics) |
| **37** | Troubleshooting Cilium: status → observe → CLI | [`tap-35-cilium-troubleshooting/`](./kubernetes-networking/k8s-lab/tap-35-cilium-troubleshooting) |
| **38** | Lab 1: Pod label sai — Hubble show "Policy denied" ngay lập tức | [`tap-36-lab-label-typo/`](./kubernetes-networking/k8s-lab/tap-36-lab-label-typo) |
| **39** | Lab 2: L7 Policy thiếu HTTP method — HTTP 403 & quy trình confirm dev | [`tap-37-lab-l7-missing-method/`](./kubernetes-networking/k8s-lab/tap-37-lab-l7-missing-method) |
| **40** | Lab 3: DNS Egress Policy & toFQDNs trap — External API fail bí ẩn | [`tap-38-lab-fqdn-trap/`](./kubernetes-networking/k8s-lab/tap-38-lab-fqdn-trap) |
| **41** | Lab 4: WireGuard MTU với Cilium — Hubble show "MTU exceeded" ngay! | [`tap-39-lab-wireguard-mtu/`](./kubernetes-networking/k8s-lab/tap-39-lab-wireguard-mtu) |

</details>

<details>
<summary><b>🔥 Phần 4 — Cilium Nâng Cao (Tập 42–46)</b></summary>

| Tập | Chủ đề | Tài liệu Lab |
| :---: | :--- | :--- |
| **42** | Cilium LB IPAM + Egress Gateway — On-prem LoadBalancer & Fixed Egress IP | [`tap-42-cilium-lb-egress/`](./kubernetes-networking/k8s-lab/tap-42-cilium-lb-egress) |
| **43** | Gateway API + Cilium Ingress — North-South Traffic path | [`tap-43-gateway-api/`](./kubernetes-networking/k8s-lab/tap-43-gateway-api) |
| **44** | Cilium Upgrade + Day-2 Operations: Upgrade không downtime, Agent crash | [`tap-44-upgrade-day2/`](./kubernetes-networking/k8s-lab/tap-44-upgrade-day2) |
| **45** | Cilium BGP Control Plane: Advertise Pod CIDRs và LoadBalancer IPs | [`tap-45-bgp-controlplane/`](./kubernetes-networking/k8s-lab/tap-45-bgp-controlplane) |
| **46** | BPF Map Sizing + Resource Tuning: Khi cluster scale lên hàng trăm pods | [`tap-46-bpf-tuning/`](./kubernetes-networking/k8s-lab/tap-46-bpf-tuning) |

</details>

<details>
<summary><b>🏆 Phần 5 — Kết & So sánh (Tập 40–41)</b></summary>

| Tập | Chủ đề | Tài liệu Lab |
| :---: | :--- | :--- |
| **40**| So sánh 3 CNI: Flannel vs Calico vs Cilium — Bảng đánh giá toàn diện | [`tap-40-cni-comparison/`](./kubernetes-networking/k8s-lab/tap-40-cni-comparison) |
| **41**| Decision Framework: Khi nào dùng Flannel, Calico, Cilium trong Production? | [`tap-41-decision-framework/`](./kubernetes-networking/k8s-lab/tap-41-decision-framework) |

</details>

---

## 🔍 2. Debug Mạng từ A-Z

> **Chẩn đoán mạng có hệ thống** — Một kỹ sư giỏi không đoán mò, họ sử dụng công cụ chuẩn xác cho từng tầng OSI (từ L1 đến L7).

* 📁 **Thư mục Lab:** [`debug-mang-az/`](./debug-mang-az)
* 📺 **Cách học:** Theo dõi các video ngắn và thực hành các câu lệnh trực tiếp trên máy ảo Linux.

| Module | Tập | Công cụ / Chủ đề | Nội dung thực hành |
| :--- | :---: | :--- | :--- |
| **Connectivity** | **01** | **ping** | ICMP, MTU Discovery, TTL Fingerprinting, Flood Ping |
| | **02** | **mtr** | Phân tích đường đi, phát hiện bottleneck, latency jitter |
| **Sockets & Ports** | **03** | **ss** | Thay thế netstat, kiểm tra TCP states, leak port, connection tracking |
| | **04** | **netcat (nc)** | Kiểm tra mở port, tạo server ảo tạm, truyền file nhanh qua socket |
| **DNS** | **05** | **dig** | Query DNS types, trace DNS delegation, debug lỗi DNS |
| **Application** | **06** | **curl** | HTTP Debug, đo lường thời gian phản hồi (timing), test proxy |
| | **07** | **openssl** | Kiểm tra cert chain, kiểm tra bắt tay TLS handshake, SNI |
| **Packet Capture** | **08** | **tcpdump** | Bắt gói tin dòng lệnh, viết biểu thức lọc (filter syntax) nâng cao |
| | **09** | **Wireshark** | Phân tích GUI, follow stream, xuất dữ liệu |
| **Performance** | **10** | **iPerf3** | Đo lường băng thông thực tế TCP/UDP, jitter, packet loss |
| **Kubernetes** | **11** | **netshoot** | Debug mạng chuyên biệt trong cụm Pod K8s |
| | **12** | **Hubble / Gadget** | Debug mạng bằng eBPF thời gian thực |

---

## 🐳 3. Container Networking (Nền tảng Linux Networking)

> Tìm hiểu cách hệ điều hành Linux tạo ra các môi trường mạng độc lập (Network Namespace) trước khi học Docker và Kubernetes.

* 📁 **Thư mục Lab:** [`container-networking/`](./container-networking)

| Bài học | Chủ đề | Mô tả thực hành |
| :--- | :--- | :--- |
| [`2.1.ip-netns/`](./container-networking/2.1.ip-netns) | Network Namespace | Tạo namespaces, kết nối các namespace cô lập bằng veth pair |
| [`2.2.bridge/`](./container-networking/2.2.bridge) | Linux Bridge | Giả lập một Switch ảo Layer 2 để kết nối nhiều namespace |
| [`2.3.iptables/`](./container-networking/2.3.iptables) | iptables | Cấu hình Firewall, thực hiện NAT (Source/Destination) trên Linux |
| [`2.4.nftables/`](./container-networking/2.4.nftables) | nftables | Tìm hiểu người kế nhiệm hiện đại, hiệu năng cao của iptables |
| [`2.5.docker-networking/`](./container-networking/2.5.docker-networking) | Docker Networking | Phân tích cơ chế mạng Bridge, Host và Overlay của Docker |
| [`hoc-bang-AI/`](./container-networking/hoc-bang-AI) | Học bằng AI | Tài liệu tương tác HTML từng bước giúp dễ dàng nắm bắt kiến thức |

---

## 🤖 4. Network Automation & FastAPI

> Tự động hóa cấu hình và quản lý thiết bị mạng từ Python cơ bản cho đến việc xây dựng một Dashboard quản lý hạ tầng mạng chuyên nghiệp bằng FastAPI.

* 📁 **Thư mục Lab:** [`network-automation/`](./network-automation)

### Python cho Network Engineer
* [`1.1-paramiko/`](./network-automation/1.1-paramiko) — Tự động kết nối SSH cơ bản với Paramiko.
* [`1.2-netmiko/`](./network-automation/1.2-netmiko) — Quản lý cấu hình đa thiết bị (Cisco, Juniper, Arista...).
* [`1.3-napalm/`](./network-automation/1.3-napalm) — Trích xuất cấu hình đồng nhất bằng NAPALM.
* [`1.4-scrapli/`](./network-automation/1.4-scrapli) — Thư viện SSH tốc độ cao, xử lý song song.
* [`1.6-python101/`](./network-automation/1.6-python101) — Python cơ bản phù hợp nhất với kỹ sư mạng.

### Tự động hóa với Ansible
* [`2.1-ansible/`](./network-automation/2.1-ansible) — Viết playbook để cấu hình hàng loạt thiết bị Switch/Router.

### Xây dựng Dashboard Quản lý Mạng bằng FastAPI
Học cách viết API và xây dựng hệ thống quản lý tập trung:
* [`3.1-fastapi-first-step/`](./network-automation/3.1-fastapi-first-step) · [`3.2-fastapi-path-params/`](./network-automation/3.2-fastapi-path-params) · [`3.3-fastapi-query-params/`](./network-automation/3.3-fastapi-query-params) (FastAPI cơ bản)
* [`3.4-request-body/`](./network-automation/3.4-request-body) · [`3.5.1-return-type/`](./network-automation/3.5.1-return-type) · [`3.5.2-reponse-model/`](./network-automation/3.5.2-reponse-model) (Xử lý dữ liệu đầu vào/ra bằng Pydantic)
* [`3.6-database/`](./network-automation/3.6-database) (Tích hợp cơ sở dữ liệu SQLModel lưu cấu hình thiết bị)
* [`containerlab/`](./network-automation/containerlab) (Dựng nhanh topology mạng lab bằng Docker container)

---

## 🐧 5. Cumulus Linux & Dynamic Routing (FRRouting)

> Xây dựng mạng Data Center thu nhỏ với hệ điều hành switch mã nguồn mở Cumulus Linux và bộ phần mềm định tuyến FRRouting.

* 📁 **Thư mục Lab:** [`cumulus-linux/`](./cumulus-linux)
* 📺 **Playlist học tập:** [FRRouting & Cumulus Linux - YouTube](https://www.youtube.com/playlist?list=PL-3AGuUf6HCrgGBtAQ8Ym3JRcMJWHxZ0j)

| Bài học | Giao thức | Nội dung bài lab |
| :--- | :---: | :--- |
| [`frr/`](./cumulus-linux/frr) | FRRouting | Cài đặt và cấu hình cơ bản daemon định tuyến trên Linux |
| [`ospf/`](./cumulus-linux/ospf) | OSPF | Cấu hình định tuyến động OSPF đa vùng (Multi-area OSPF) |
| [`vxlan-la-gi/`](./cumulus-linux/vxlan-la-gi) | VXLAN | Thiết lập mạng Overlay Layer 2 trên hạ tầng định tuyến Layer 3 |

---

## 🔬 6. Wireshark Thực Chiến

> "Gói tin không biết nói dối". Kỹ năng phân tích gói tin nâng cao để phát hiện sự cố hiệu năng và các dấu hiệu tấn công mạng.

* 📁 **Thư mục Lab:** [`wireshark/`](./wireshark)
* 📺 **Playlist học tập:** [Wireshark Thực Chiến - YouTube](https://www.youtube.com/playlist?list=PL-3AGuUf6HCpLvQl_ETF-1zVM-Pu-cJ4X)

* [`4.6.thuc-chien-export-objects/`](./wireshark/4.6.thuc-chien-export-objects) — Kỹ thuật trích xuất tệp tin (Export Objects) từ file capture PCAP, ứng dụng trong điều tra bảo mật và Forensic.

---

## 🤝 Đóng góp cho Dự án (Contributing)

Mọi đóng góp giúp tài liệu hoàn thiện hơn đều vô cùng đáng quý! Nếu bạn:
1. Phát hiện lỗi chính tả hoặc lỗi kỹ thuật trong tài liệu lab.
2. Có thêm các bài lab thực tế hay muốn chia sẻ.
3. Muốn tối ưu hóa các script cài đặt lab.

Hãy thoải mái tạo một **Pull Request** hoặc mở một **Issue** trên trang chủ GitHub của dự án!

---

## 📺 Theo dõi Kênh YouTube Network Thực Chiến

Đừng bỏ lỡ các tập bài học mới nhất! Đăng ký kênh và bật chuông thông báo 🔔:

👉 **[youtube.com/@NetworkThucChien](https://www.youtube.com/@NetworkThucChien)**
