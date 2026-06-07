# 🌐 Network Thực Chiến

> **Tài liệu thực hành đồng hành cùng kênh YouTube [Network Thực Chiến](https://www.youtube.com/@NetworkThucChien)**

Đây là kho lưu trữ tổng hợp tất cả tài liệu, cấu hình mẫu, bài lab và slide trình bày được sử dụng trong các video trên kênh. Nội dung được xây dựng theo triết lý **"Học bằng cách thực hành"** — mỗi khái niệm mạng đều đi kèm với bài lab thực chiến có thể tự dựng ngay trên máy tính cá nhân.

[![YouTube](https://img.shields.io/badge/YouTube-Network%20Thực%20Chiến-red?style=flat&logo=youtube)](https://www.youtube.com/@NetworkThucChien)
[![GitHub Stars](https://img.shields.io/github/stars/thangphan205/network-thuc-chien?style=flat)](https://github.com/thangphan205/network-thuc-chien)

---

## 📂 Cấu trúc Repository

| Thư mục | Chủ đề | Mô tả |
| :--- | :--- | :--- |
| [`kubernetes-networking/`](#-kubernetes-networking) | ☸️ Kubernetes Networking | Series 42 tập: Flannel → Calico → Cilium, từ Linux kernel đến production |
| [`container-networking/`](#-container-networking) | 🐳 Container Networking | Linux Networking nền tảng: netns, bridge, iptables, nftables, Docker |
| [`network-automation/`](#-network-automation) | 🤖 Network Automation | Python, Ansible, FastAPI, Containerlab |
| [`cumulus-linux/`](#-cumulus-linux) | 🐧 Cumulus Linux | BGP/OSPF/VXLAN với FRRouting và Cumulus |
| [`wireshark/`](#-wireshark) | 🔬 Wireshark | Phân tích gói tin thực chiến |
| [`opensource-tools/`](#-opensource-tools) | 🛠 Open-source Tools | Giới thiệu và hướng dẫn các công cụ hữu ích |
| [`do-vui/`](#-do-vui) | 🎮 Đố Vui | Các bài thực hành thú vị, CTF-style |

---

## ☸️ Kubernetes Networking

> **Series chuyên sâu 42 tập** — Kubernetes Networking & NetworkPolicy từ Linux kernel đến production.

📁 [`kubernetes-networking/`](./kubernetes-networking)

Khóa học **bỏ qua khái niệm cơ bản**, đi thẳng vào kiến trúc mạng, Data Plane và cách K8s thao tác với Linux kernel (namespaces, veth pairs, iptables, eBPF). Ba CNI được mổ xẻ sâu: **Flannel → Calico → Cilium**.

### Môi trường Lab

📁 [`k8s-lab/tap-00-setup-lab/`](./kubernetes-networking/k8s-lab/tap-00-setup-lab)

**Full VM** (không phải `kind`/`minikube`) — toàn quyền can thiệp kernel:

| File | Mục đích |
| :--- | :--- |
| [`k8s-node.yaml`](./kubernetes-networking/k8s-lab/tap-00-setup-lab/k8s-node.yaml) | cloud-init: cài containerd + kubeadm + kubelet tự động |
| [`setup-lab.sh`](./kubernetes-networking/k8s-lab/tap-00-setup-lab/setup-lab.sh) | Dựng 3-node cluster (1 lệnh) · hỗ trợ `flannel\|calico\|cilium` |
| [`reset-lab.sh`](./kubernetes-networking/k8s-lab/tap-00-setup-lab/reset-lab.sh) | Reset cluster (giữ VM) hoặc xóa hoàn toàn |

```bash
./setup-lab.sh            # dựng cluster, không cài CNI
./setup-lab.sh flannel    # + Flannel (Tập 6-10)
./setup-lab.sh calico     # + Calico (Tập 11-23)
./setup-lab.sh cilium     # + Cilium (Tập 24-40)
```

### Lộ trình học tập

**⚪ Phần 0 — Nền tảng (Tập 1–5)**

| Tập | Chủ đề | Lab |
| :---: | :--- | :--- |
| **0** | Setup Lab — Multipass + cloud-init + kubeadm | [`tap-00-setup-lab/`](./kubernetes-networking/k8s-lab/tap-00-setup-lab) |
| **1** | Kubernetes Network Model: 4 nguyên tắc không NAT | [`tap-01.md`](./kubernetes-networking/k8s-lab/tap-01.md) |
| **2** | Pod Network: Pause Container, veth pair & Network Namespace | [`tap-02.md`](./kubernetes-networking/k8s-lab/tap-02.md) |
| **3** | Services & kube-proxy: ClusterIP, NodePort, LoadBalancer từ góc nhìn packet | [`tap-03.md`](./kubernetes-networking/k8s-lab/tap-03.md) |
| **4** | CoreDNS & Thuế "ndots:5": Tại sao mỗi request tốn 5 DNS query? | [`tap-04.md`](./kubernetes-networking/k8s-lab/tap-04.md) |
| **5** | CNI là gì? Hành trình cắm mạng cho Pod từ ADD đến DEL | [`tap-05.md`](./kubernetes-networking/k8s-lab/tap-05.md) |

**🟡 Phần 1 — Flannel (Tập 6–10)**

| Tập | Chủ đề | Lab |
| :---: | :--- | :--- |
| **6** | Flannel là gì? Vấn đề Pod-to-Pod Communication | [`tap-06.md`](./kubernetes-networking/k8s-lab/tap-06.md) |
| **7** | Kiến trúc Flannel: flanneld, etcd và CNI plugin | [`tap-07.md`](./kubernetes-networking/k8s-lab/tap-07.md) |
| **8** | VXLAN Backend: Flannel đóng gói packet như thế nào? (50 bytes overhead) | [`tap-08.md`](./kubernetes-networking/k8s-lab/tap-08.md) |
| **9** | host-gw Mode: Khi nào bỏ encapsulation để tăng tốc? | [`tap-09.md`](./kubernetes-networking/k8s-lab/tap-09.md) |
| **10** | Giới hạn của Flannel: Tại sao không có NetworkPolicy? | [`tap-10.md`](./kubernetes-networking/k8s-lab/tap-10.md) |

**🔵 Phần 2 — Calico (Tập 11–26)**

| Tập | Chủ đề | Lab |
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
| **20** | Lab 1: "Pod thiếu label" — Connection Timeout không rõ lý do | [`tap-18-lab-1/`](./kubernetes-networking/k8s-lab/tap-18-lab-1) |
| **21** | Lab 2: BGP không quảng bá Pod CIDR — Server vật lý không ping được Pod | [`tap-19-lab-2/`](./kubernetes-networking/k8s-lab/tap-19-lab-2) |
| **22** | Lab 3: WireGuard MTU & PMTUD Black Hole — File nhỏ ok, file lớn fail | [`tap-20-lab-3/`](./kubernetes-networking/k8s-lab/tap-20-lab-3) |
| **23** | Lab 4: Cross-namespace AND/OR Bug — Prometheus không scrape được Backend | [`tap-21-lab-4/`](./kubernetes-networking/k8s-lab/tap-21-lab-4) |
| **24** | Tổng kết & Workflow Troubleshooting Calico chuẩn | [`tap-22-calico-troubleshooting/`](./kubernetes-networking/k8s-lab/tap-22-calico-troubleshooting) |
| **25** | Calico Observability: Prometheus + Grafana + AlertManager | [`tap-23-calico-observability/`](./kubernetes-networking/k8s-lab/tap-23-calico-observability) |

**🟣 Phần 3 — Cilium (Tập 24–43)**

| Tập | Chủ đề | Lab |
| :---: | :--- | :--- |
| **26** | Tại sao Cilium? Pain points của Calico & sockops bypass | [`tap-24-cilium-why/`](./kubernetes-networking/k8s-lab/tap-24-cilium-why) |
| **27** | BPF Maps: Hash, LRU, Array, Per-CPU — Vũ khí hiệu năng của Cilium | [`tap-25-bpf-maps/`](./kubernetes-networking/k8s-lab/tap-25-bpf-maps) |
| **28** | Kiến trúc Cilium: Operator, Agent, GoBGP, Hubble — So sánh với Calico | [`tap-26-cilium-architecture/`](./kubernetes-networking/k8s-lab/tap-26-cilium-architecture) |
| **29** | 3 Hook Points của eBPF: XDP, TC và sockops | [`tap-27-ebpf-hooks/`](./kubernetes-networking/k8s-lab/tap-27-ebpf-hooks) |
| **30** | Cùng Node vs Khác Node: Tại sao sockops bypass hoàn toàn XDP/TC? | [`tap-28-same-node-vs-cross-node/`](./kubernetes-networking/k8s-lab/tap-28-same-node-vs-cross-node) |
| **31** | L3/L4 Policy trong Cilium: So sánh với Kubernetes NetworkPolicy | [`tap-29-cilium-l3l4-policy/`](./kubernetes-networking/k8s-lab/tap-29-cilium-l3l4-policy) |
| **32** | L7 Policy: Chặn HTTP POST theo path với Envoy Proxy | [`tap-30-cilium-l7-policy/`](./kubernetes-networking/k8s-lab/tap-30-cilium-l7-policy) |
| **33** | DNS Policy với toFQDNs: Filter theo domain thay vì IP | [`tap-31-fqdn-dns-policy/`](./kubernetes-networking/k8s-lab/tap-31-fqdn-dns-policy) |
| **34** | Cilium + Istio: Khi nào kết hợp, khi nào dùng Cilium thuần? | [`tap-32-cilium-vs-istio/`](./kubernetes-networking/k8s-lab/tap-32-cilium-vs-istio) |
| **35** | Hubble CLI: `hubble observe` — Debug real-time không cần SSH | [`tap-33-hubble-cli/`](./kubernetes-networking/k8s-lab/tap-33-hubble-cli) |
| **36** | Hubble UI: Service Map tự động & DROPPED màu đỏ | [`tap-34-hubble-ui/`](./kubernetes-networking/k8s-lab/tap-34-hubble-ui) |
| **37** | Hubble Metrics: hubble_drop_total, http_requests — Đúng tool, đúng tình huống | [`tap-35-hubble-metrics/`](./kubernetes-networking/k8s-lab/tap-35-hubble-metrics) |
| **38** | Troubleshooting Cilium: status → observe → CLI | [`tap-36-cilium-troubleshooting/`](./kubernetes-networking/k8s-lab/tap-36-cilium-troubleshooting) |
| **39** | Lab 1: Pod label sai — Hubble show "Policy denied" ngay lập tức | [`tap-37-lab-label-typo/`](./kubernetes-networking/k8s-lab/tap-37-lab-label-typo) |
| **40** | Lab 2: L7 Policy thiếu HTTP method — HTTP 403 & quy trình confirm dev | [`tap-38-lab-l7-missing-method/`](./kubernetes-networking/k8s-lab/tap-38-lab-l7-missing-method) |
| **41** | Lab 3: DNS Egress Policy & toFQDNs trap — External API fail bí ẩn | [`tap-39-lab-fqdn-trap/`](./kubernetes-networking/k8s-lab/tap-39-lab-fqdn-trap) |
| **42** | Lab 4: WireGuard MTU với Cilium — Hubble show "MTU exceeded" ngay! | [`tap-40-lab-wireguard-mtu/`](./kubernetes-networking/k8s-lab/tap-40-lab-wireguard-mtu) |

**🏆 Phần 4 — Kết (Tập 41–45)**

| Tập | Chủ đề | Lab |
| :---: | :--- | :--- |
| **43** | So sánh 3 CNI: Flannel vs Calico vs Cilium — Bảng đánh giá toàn diện | [`tap-41-cni-comparison/`](./kubernetes-networking/k8s-lab/tap-41-cni-comparison) |
| **44** | Decision Framework: Khi nào dùng Flannel, Calico, Cilium trong Production? | [`tap-42-decision-framework/`](./kubernetes-networking/k8s-lab/tap-42-decision-framework) |

---

## 🐳 Container Networking

> **Nền tảng Linux Networking** — Hiểu sâu trước khi học Docker và Kubernetes.

📁 [`container-networking/`](./container-networking)

| Thư mục | Nội dung |
| :--- | :--- |
| [`2.1.ip-netns/`](./container-networking/2.1.ip-netns) | Network Namespace: cô lập mạng ở cấp Linux |
| [`2.2.bridge/`](./container-networking/2.2.bridge) | Linux Bridge: switch ảo kết nối các namespace |
| [`2.3.iptables/`](./container-networking/2.3.iptables) | iptables: tường lửa và NAT trên Linux |
| [`2.4.nftables/`](./container-networking/2.4.nftables) | nftables: người kế nhiệm hiện đại của iptables |
| [`2.5.docker-networking/`](./container-networking/2.5.docker-networking) | Docker Networking: bridge, host, overlay |
| [`hoc-bang-AI/`](./container-networking/hoc-bang-AI) | Tài liệu học tương tác theo từng bước (HTML) |

---

## 🤖 Network Automation

> **Tự động hóa mạng** từ Python cơ bản đến xây dựng ứng dụng quản lý bằng FastAPI.

📁 [`network-automation/`](./network-automation)

**Series 1: Python cho Network Engineer**

| Thư mục | Nội dung |
| :--- | :--- |
| [`1.1-paramiko/`](./network-automation/1.1-paramiko) | SSH tự động bằng thư viện Paramiko |
| [`1.2-netmiko/`](./network-automation/1.2-netmiko) | Netmiko: SSH đa vendor (Cisco, Juniper, Arista...) |
| [`1.3-napalm/`](./network-automation/1.3-napalm) | NAPALM: Network Abstraction Layer |
| [`1.4-scrapli/`](./network-automation/1.4-scrapli) | Scrapli: thư viện kết nối hiệu năng cao |
| [`1.6-python101/`](./network-automation/1.6-python101) | Python cơ bản dành cho Network Engineer |

**Series 2: Ansible**

| Thư mục | Nội dung |
| :--- | :--- |
| [`2.1-ansible/`](./network-automation/2.1-ansible) | Ansible: quản lý cấu hình không cần agent |

**Series 3: FastAPI — Xây dựng API quản lý mạng**

| Thư mục | Nội dung |
| :--- | :--- |
| [`3.1-fastapi-first-step/`](./network-automation/3.1-fastapi-first-step) | Bước đầu với FastAPI |
| [`3.2-fastapi-path-params/`](./network-automation/3.2-fastapi-path-params) | Path Parameters |
| [`3.3-fastapi-query-params/`](./network-automation/3.3-fastapi-query-params) | Query Parameters |
| [`3.4-request-body/`](./network-automation/3.4-request-body) | Request Body & Pydantic |
| [`3.5.1-return-type/`](./network-automation/3.5.1-return-type) | Response Type & Validation |
| [`3.5.2-reponse-model/`](./network-automation/3.5.2-reponse-model) | Response Model |
| [`3.6-database/`](./network-automation/3.6-database) | Kết nối Database |
| [`containerlab/`](./network-automation/containerlab) | Containerlab: topology lab bằng container |

---

## 🐧 Cumulus Linux

> **Mạng doanh nghiệp** với FRRouting trên Cumulus Linux — BGP, OSPF, VXLAN thực chiến.

📁 [`cumulus-linux/`](./cumulus-linux)

| Thư mục | Nội dung |
| :--- | :--- |
| [`frr/`](./cumulus-linux/frr) | FRRouting: cấu hình routing protocol mã nguồn mở |
| [`ospf/`](./cumulus-linux/ospf) | OSPF: bài lab định tuyến nội bộ |
| [`vxlan-la-gi/`](./cumulus-linux/vxlan-la-gi) | VXLAN: mạng overlay Layer 2 over Layer 3 |

---

## 🔬 Wireshark

> **Phân tích gói tin** — Kỹ năng không thể thiếu của Network Engineer.

📁 [`wireshark/`](./wireshark)

| Thư mục | Nội dung |
| :--- | :--- |
| [`4.6.thuc-chien-export-objects/`](./wireshark/4.6.thuc-chien-export-objects) | Export Objects: khai thác file từ gói tin capture |

---

## 🛠 Opensource Tools

> **Công cụ mã nguồn mở** hữu ích trong vận hành, giám sát và kiểm thử hệ thống.

📁 [`opensource-tools/`](./opensource-tools)

| Công cụ | Mô tả | Tài liệu |
| :--- | :--- | :--- |
| **Multipass** | Tạo máy ảo Ubuntu siêu tốc (Full-VM cho macOS/Linux/Windows) | [`multipass/`](./opensource-tools/multipass) |
| **MTR** | Khám bệnh mạng toàn diện — kết hợp Ping + Traceroute | [`mtr/`](./opensource-tools/mtr) |
| *(Sắp ra)* | Vagrant, Ansible, Prometheus & Grafana, netshoot, iPerf3, Wireshark, K6... | — |

---

## 🎮 Đố Vui

> Các bài thực hành thú vị, thử thách mạng theo phong cách CTF.

📁 [`do-vui/`](./do-vui)

---

## 🤝 Đóng góp

Bạn có bài lab hay, ví dụ cấu hình mới, hoặc phát hiện lỗi trong tài liệu? Hãy tạo **Pull Request** hoặc mở **Issue** — mọi đóng góp đều được chào đón!

---

## 📺 Theo dõi kênh

Đừng quên **Subscribe** và bật thông báo 🔔 để không bỏ lỡ các tập mới!

**[👉 youtube.com/@NetworkThucChien](https://www.youtube.com/@NetworkThucChien)**
