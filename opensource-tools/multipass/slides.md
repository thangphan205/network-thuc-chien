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
  .good { color: #68d391; font-weight: bold; }
  .bad  { color: #fc8181; font-weight: bold; }
  .warn { color: #f6ad55; font-weight: bold; }
---

<!-- _class: title -->

# Multipass
## VM tốc độ Container — cho Network & Security Engineer

**Network Thực Chiến** · Series: Công cụ Open-Source · Tập 01

---

## Nội dung

1. **Vấn đề** — VMware quá nặng, Docker thiếu kernel
2. **Multipass là gì?** — CLI từ Canonical, Ubuntu VM trong vài giây
3. **Kiến trúc** — Native Hypervisor theo từng OS
4. **So sánh** — Multipass vs Docker vs Vagrant vs VMware
5. **Cài đặt & Lệnh cơ bản** — Cheatsheet đầy đủ
6. **Cloud-init** — Provision VM tự động, không cần SSH thủ công
7. **Ứng dụng thực chiến** — Network lab, security sandbox

---

<!-- _class: divider -->

# Phần 1
## Vấn đề của kỹ sư hạ tầng

---

## VMware / VirtualBox — Quá nặng

Khi cần lab nhanh, bạn phải:

```
1. Tải file ISO (~1GB)
2. Tạo VM trong GUI, cấu hình RAM/CPU/Disk
3. Cài đặt OS qua wizard (20–30 phút)
4. Cài thêm VMware Tools / Guest Additions
5. Snapshot trước khi thay đổi
→ Tổng: 45 phút cho 1 VM sạch
```

**Hậu quả:**
- Mỗi VM ăn 20–40GB disk (full OS image)
- GUI nặng, không tự động hóa được
- Không phù hợp để dựng nhanh rồi xóa

---

## Docker — Nhanh nhưng thiếu kernel

Docker là lựa chọn tốt cho microservice, nhưng hạn chế với network/security lab:

| Yêu cầu lab | Docker | Lý do |
|:---|:---|:---|
| `iptables` / `nftables` toàn phần | ⚠️ Hạn chế | Chung kernel với host |
| Test `systemd` service | ❌ Khó | Container không có `systemd` mặc định |
| Cô lập kernel module | ❌ Không | Container share kernel space |
| Lab routing giữa các node | ⚠️ Phức tạp | Cần `--cap-add=NET_ADMIN` + cấu hình thêm |
| Phân tích mã độc | ❌ Nguy hiểm | Không cô lập hoàn toàn |

> Cần giải pháp: **Full VM** (kernel riêng) nhưng có tốc độ và workflow của Container.

---

<!-- _class: divider -->

# Phần 2
## Multipass là gì?

---

## Multipass — VM trong vài giây

**Multipass** là CLI tool từ **Canonical** để quản lý Ubuntu VM tức thì.

```bash
$ multipass launch 24.04 -n lab01
Launched: lab01

$ multipass shell lab01
Welcome to Ubuntu 24.04 LTS
ubuntu@lab01:~$
```

**Thời gian: ~15 giây** (image đã cache), ~2 phút lần đầu tải.

**Điểm khác biệt:**
- Kernel **riêng biệt** hoàn toàn — không share với host
- Tự động hóa: tải image, tạo VM, cấu hình mạng — chỉ 1 lệnh
- Xóa sạch không để lại dấu vết: `multipass delete && multipass purge`
- 100% CLI — có thể script hóa, CI/CD

---

## Kiến trúc — Native Hypervisor

Multipass **không tự build hypervisor** — nó dùng hypervisor tốt nhất có sẵn theo từng OS:

| Platform | Hypervisor mặc định | Ghi chú |
|:---|:---|:---|
| **macOS Intel** | QEMU | Ổn định, hiệu năng tốt |
| **macOS Apple Silicon** | Apple Virtualization Framework | Tối ưu native cho M1/M2/M3/M4 |
| **Linux** | KVM / QEMU | Hiệu năng gần bare-metal |
| **Windows** | Hyper-V | Yêu cầu bật Hyper-V trong BIOS |

**Kết quả:** VM Ubuntu thực thụ, kernel riêng, khởi động 5–15 giây — nhanh như chớp nhờ tận dụng virtualization layer của OS.

---

<!-- _class: divider -->

# Phần 3
## So sánh

---

## Multipass vs Các công cụ khác

| Tiêu chí | Multipass | Docker | Vagrant + VirtualBox | VMware/ESXi |
|:---|:---|:---|:---|:---|
| **Mức ảo hóa** | Full OS (kernel riêng) | Container (chung kernel) | Full OS (kernel riêng) | Bare-metal / Type 1 |
| **Khởi động** | ~5–15s | ~1s | ~30–60s | Rất chậm |
| **Tài nguyên** | Thấp (native hypervisor) | Thấp nhất | Cao (GUI overhead) | Rất cao |
| **Lab mạng sâu** | ✅ Tuyệt đối | ⚠️ Hạn chế | ✅ Tốt nhưng nặng | ✅ Tuyệt đối |
| **systemd đầy đủ** | ✅ | ❌ | ✅ | ✅ |
| **Tự động hóa** | ✅ CLI + cloud-init | ✅ Dockerfile | ⚠️ Vagrantfile (phức tạp hơn) | ❌ Cần vCenter/API |
| **OS hỗ trợ** | Chỉ Ubuntu | Đa dạng | Đa dạng | Đa dạng |

> **Kết luận:** Multipass lấp đúng khoảng trống — nhanh như Docker, đầy đủ như VMware, nhẹ hơn Vagrant.

---

<!-- _class: divider -->

# Phần 4
## Cài đặt & Lệnh cơ bản

---

## Cài đặt

**macOS (Homebrew — khuyên dùng):**
```bash
brew install --cask multipass
```

**Linux (Snap):**
```bash
sudo snap install multipass
```

**Windows:**
Tải file `.exe` từ [canonical.com/multipass](https://canonical.com/multipass). Yêu cầu bật Hyper-V.

---

**Kiểm tra cài đặt:**
```bash
multipass version
# multipass  1.14.1+mac
# multipassd 1.14.1+mac
```

---

## Cheatsheet — Vòng đời VM

```bash
# Xem các Ubuntu image có sẵn
multipass find

# Launch VM Ubuntu 24.04 mặc định
multipass launch 24.04

# Launch với cấu hình tùy chỉnh
multipass launch -c 2 -m 4G -d 20G -n security-lab 24.04

# Xem danh sách VM
multipass list

# Xem thông tin chi tiết
multipass info security-lab

# Vào shell VM
multipass shell security-lab

# Chạy lệnh không cần vào shell
multipass exec security-lab -- ip addr show
```

---

## Cheatsheet — Quản lý & Mount

```bash
# Mount thư mục từ host vào VM
multipass mount ./lab-scripts security-lab:/home/ubuntu/scripts

# Unmount
multipass umount security-lab

# Copy file vào/ra VM
multipass transfer ./config.yaml security-lab:/home/ubuntu/

# Dừng / Start VM
multipass stop security-lab
multipass start security-lab

# Snapshot & Restore
multipass snapshot security-lab --name clean-state
multipass restore security-lab.clean-state

# Xóa sạch không để lại dấu vết
multipass delete security-lab && multipass purge
```

---

## `multipass find` — Xem image có sẵn

```bash
$ multipass find

Image                   Aliases           Version          Remote
20.04                   focal             20240821         Ubuntu
22.04                   jammy             20240912         Ubuntu
24.04                   noble,lts         20241004         Ubuntu
24.10                   oracular          20240911         Ubuntu

Blueprint               Aliases           Version          Remote
anbox-cloud-appliance                     latest           Canonical
charm-dev                                 latest           Canonical
docker                                    0.4              Canonical
jellyfin                                  latest           Canonical
minikube                                  latest           Canonical
```

> Blueprint `docker`, `minikube` là môi trường pre-configured — launch xong dùng ngay.

---

<!-- _class: divider -->

# Phần 5
## Cloud-init — Provision VM tự động

---

## Cloud-init là gì?

**Cloud-init** là tiêu chuẩn industry để tự động hóa provisioning VM khi khởi động lần đầu.

**Không có cloud-init:**
```
launch VM → shell vào → apt install → cấu hình → sẵn sàng
→ Lặp lại thủ công mỗi lần
```

**Với cloud-init:**
```
launch VM --cloud-init config.yaml → VM sẵn sàng hoàn toàn
→ Tự động: cài package, tạo user, copy file, chạy script
```

```bash
multipass launch -n lab01 --cloud-init config.yaml
```

---

## Cloud-init — Ví dụ thực tế

```yaml
# config.yaml — Dựng network-lab node tự động
#cloud-config
packages:
  - tcpdump
  - iproute2
  - iperf3
  - nmap
  - python3-pip

package_update: true

runcmd:
  - sysctl -w net.ipv4.ip_forward=1
  - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  - ip route add 10.20.0.0/16 via 192.168.64.1

write_files:
  - path: /home/ubuntu/lab-ready
    content: "Network lab node ready\n"
```

```bash
multipass launch -n router-node -c 2 -m 2G --cloud-init config.yaml
```

**Kết quả:** VM khởi động xong là có đủ tools, IP forward bật, route cấu hình sẵn — không cần SSH thủ công.

---

## Cloud-init — Lab Multi-node

Tạo nhiều node cho bài lab một lúc:

```bash
#!/bin/bash
# Dựng topology: client → router → server

multipass launch -n client  -c 1 -m 1G --cloud-init client.yaml  24.04
multipass launch -n router  -c 2 -m 2G --cloud-init router.yaml  24.04
multipass launch -n server  -c 1 -m 1G --cloud-init server.yaml  24.04

echo "Topology sẵn sàng:"
multipass list
```

```
Name    State    IPv4             Image
client  Running  192.168.64.10    Ubuntu 24.04 LTS
router  Running  192.168.64.11    Ubuntu 24.04 LTS
server  Running  192.168.64.12    Ubuntu 24.04 LTS
```

> Dựng 3-node lab từ script: ~45 giây. Xóa sạch: 1 lệnh.

---

<!-- _class: divider -->

# Phần 6
## Ứng dụng thực chiến

---

## Use case 1 — Network Automation Lab

Test script cấu hình trên môi trường sạch trước khi đưa lên thiết bị thật:

```bash
# Dựng node Ubuntu sạch
multipass launch -n test-node -c 2 -m 2G 24.04

# Mount scripts từ host
multipass mount ./automation-scripts test-node:/home/ubuntu/scripts

# Chạy thử
multipass exec test-node -- bash /home/ubuntu/scripts/configure-routing.sh

# Xem kết quả
multipass exec test-node -- ip route show

# Xóa sạch sau khi test
multipass delete test-node && multipass purge
```

**Lợi ích:** Mỗi lần test là môi trường hoàn toàn sạch — không còn "works on my machine".

---

## Use case 2 — Security Sandbox

Phân tích mã độc hoặc chạy tool nguy hiểm trong môi trường cô lập:

```bash
# Tạo sandbox cô lập
multipass launch -n malware-sandbox -c 2 -m 4G 22.04

# Vào sandbox
multipass shell malware-sandbox

# Bên trong sandbox — làm gì thì làm
ubuntu@malware-sandbox:~$ wget http://suspicious-url/payload
ubuntu@malware-sandbox:~$ strace ./payload
ubuntu@malware-sandbox:~$ tcpdump -i any -w capture.pcap &

# Thoát ra host
exit

# Lấy file capture về host
multipass transfer malware-sandbox:/home/ubuntu/capture.pcap ./

# Xóa sạch hoàn toàn — không để lại dấu vết trên host
multipass delete malware-sandbox && multipass purge
```

---

## Use case 3 — Dựng Backend Test cho Open-Source Tools

Lab thực chiến với các project trong series này:

```bash
# Dựng backend tacacs-ng để test tacacs-ng-ui
multipass launch --cloud-init tacacs-setup.yaml -n tacacs-server 22.04

# Dựng syslog server để test NetConsole  
multipass launch --cloud-init syslog-setup.yaml -n syslog-server 24.04

# Dựng môi trường Kubernetes nhẹ
multipass launch minikube -n k8s-lab -c 4 -m 8G
multipass shell k8s-lab
ubuntu@k8s-lab:~$ minikube start
```

> Mỗi project trong series đều có thể dựng backend test bằng Multipass + cloud-init trong vài phút.

---

## Key Takeaways

| Tình huống | Dùng gì |
|:---|:---|
| Cần lab mạng sâu (iptables, routing, kernel) | **Multipass** |
| Cần cô lập hoàn toàn với host | **Multipass** |
| Cần provision nhiều node giống nhau | **Multipass + cloud-init** |
| Cần run microservice, CI/CD | Docker |
| Cần hỗ trợ nhiều OS khác nhau | Vagrant |

**Bộ lệnh cốt lõi:**
```bash
multipass launch -c 2 -m 4G -n mylab 24.04       # Tạo VM
multipass launch -n mylab --cloud-init cfg.yaml   # Tạo VM + provision
multipass shell mylab                             # Vào VM
multipass exec mylab -- <command>                 # Chạy lệnh
multipass delete mylab && multipass purge         # Xóa sạch
```

---

<!-- _class: title -->

# Cảm ơn đã theo dõi!

**Network Thực Chiến**


> *"Full VM power, Container speed — launch once, purge clean."*
