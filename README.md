# 🌐 Network Thực Chiến

> **Tài liệu thực hành đồng hành cùng kênh YouTube [Network Thực Chiến](https://www.youtube.com/@NetworkThucChien)**

Đây là kho lưu trữ tổng hợp tất cả tài liệu, cấu hình mẫu, bài lab và slide trình bày được sử dụng trong các video trên kênh. Nội dung được xây dựng theo triết lý **"Học bằng cách thực hành"** — mỗi khái niệm mạng đều đi kèm với bài lab thực chiến có thể tự dựng ngay trên máy tính cá nhân.

[![YouTube](https://img.shields.io/badge/YouTube-Network%20Thực%20Chiến-red?style=flat&logo=youtube)](https://www.youtube.com/@NetworkThucChien)
[![GitHub Stars](https://img.shields.io/github/stars/thangphan205/network-thuc-chien?style=flat)](https://github.com/thangphan205/network-thuc-chien)

---

## 📂 Cấu trúc Repository

| Thư mục | Chủ đề | Mô tả |
| :--- | :--- | :--- |
| [`kubernetes-networking/`](#-kubernetes-networking) | ☸️ Kubernetes Networking | Series 15 tập học chuyên sâu về mạng K8s |
| [`container-networking/`](#-container-networking) | 🐳 Container Networking | Linux Networking nền tảng: netns, bridge, iptables, nftables, Docker |
| [`network-automation/`](#-network-automation) | 🤖 Network Automation | Python, Ansible, FastAPI, Containerlab |
| [`cumulus-linux/`](#-cumulus-linux) | 🐧 Cumulus Linux | BGP/OSPF/VXLAN với FRRouting và Cumulus |
| [`wireshark/`](#-wireshark) | 🔬 Wireshark | Phân tích gói tin thực chiến |
| [`opensource-tools/`](#-opensource-tools) | 🛠 Open-source Tools | Giới thiệu và hướng dẫn các công cụ hữu ích |
| [`do-vui/`](#-do-vui) | 🎮 Đồ Vui | Các bài thực hành thú vị, CTF-style |

---

## ☸️ Kubernetes Networking

> **Series chuyên sâu 15 tập** dành cho Network Engineer muốn hiểu cơ chế mạng bên dưới của Kubernetes.

📁 [`kubernetes-networking/`](./kubernetes-networking)

Khóa học này **bỏ qua khái niệm cơ bản**, đi thẳng vào kiến trúc mạng, Data Plane và cách K8s thao tác với Linux kernel (namespaces, veth pairs, iptables, eBPF).

### Lộ trình học tập

| Tập | Chủ đề | Tài liệu Lab |
| :---: | :--- | :--- |
| **Tập 0** | Setup Home Lab (Vagrant/Multipass + kubeadm) | [`lab-module0/`](./kubernetes-networking/lab-module0) |
| **Tập 1** | Network Model & Bí mật bên trong Pod | [`lab-module1/1.1-network-model-pod/`](./kubernetes-networking/lab-module1/1.1-network-model-pod) |
| **Tập 2** | CNI Specification v1.1.0 hoạt động ra sao? | [`lab-module1/1.2-cni-specification/`](./kubernetes-networking/lab-module1/1.2-cni-specification) |
| **Tập 3** | Kube-proxy & Bài toán Services | [`lab-module1/1.3-kube-proxy-services/`](./kubernetes-networking/lab-module1/1.3-kube-proxy-services) |
| **Tập 4** | DNS trong Kubernetes & Thuế "ndots" | [`lab-module1/1.4-dns-ndots/`](./kubernetes-networking/lab-module1/1.4-dns-ndots) |
| **Tập 5** | Cuộc chuyển giao Ingress → Gateway API | [`lab-module1/1.5-ingress-gateway-api/`](./kubernetes-networking/lab-module1/1.5-ingress-gateway-api) |
| **Tập 6** | Bảo mật với NetworkPolicy | [`lab-module1/1.6-network-policy/`](./kubernetes-networking/lab-module1/1.6-network-policy) |
| **Tập 7** | Flannel Deep Dive (VXLAN & host-gw) | *(Sắp ra)* |
| **Tập 8** | Calico (Phần 1): Kiến trúc & IPAM | *(Sắp ra)* |
| **Tập 9** | Calico (Phần 2): Native BGP & eBPF | *(Sắp ra)* |
| **Tập 10** | Cilium (Phần 1): eBPF & Identity Security | *(Sắp ra)* |
| **Tập 11** | Cilium (Phần 2): Kube-proxy Replacement | *(Sắp ra)* |
| **Tập 12** | Observability & Troubleshooting | *(Sắp ra)* |
| **Tập 13** | CNI Performance & Benchmarking | *(Sắp ra)* |
| **Tập 14** | K8s Networking trên Cloud | *(Sắp ra)* |
| **Tập 15** | Capstone Project (Trận chiến cuối cùng) | *(Sắp ra)* |

### Môi trường Lab
Khóa học sử dụng **Full VM** (không phải `kind`/`minikube`) để có toàn quyền can thiệp kernel:
- **Windows/Linux:** Vagrant + VirtualBox
- **macOS (Apple Silicon):** Multipass

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

## 🎮 Đồ Vui

> Các bài thực hành thú vị, thử thách mạng theo phong cách CTF.

📁 [`do-vui/`](./do-vui)

---

## 🤝 Đóng góp

Bạn có bài lab hay, ví dụ cấu hình mới, hoặc phát hiện lỗi trong tài liệu? Hãy tạo **Pull Request** hoặc mở **Issue** — mọi đóng góp đều được chào đón!

---

## 📺 Theo dõi kênh

Đừng quên **Subscribe** và bật thông báo 🔔 để không bỏ lỡ các tập mới!

**[👉 youtube.com/@NetworkThucChien](https://www.youtube.com/@NetworkThucChien)**
