# 🔬 Lab Cơm Thêm: Mô Phỏng MTU Blackhole Đầy Đủ Qua Router / Firewall Trung Gian

> 💡 **Mục đích:** Lab nâng cao dành cho học viên muốn đào sâu thực tế hạ tầng Enterprise/Cloud — nơi Client và Server nằm ở 2 phân đoạn mạng riêng biệt và đi qua Router/Firewall trung gian (với MTU đường WAN bị bóp nhỏ do VPN/Tunnel).

---

## 🗺️ Sơ Đồ Kiến Trúc Mạng 3 Nodes

```
+----------------------------------------------------------------------------------------------------+
|                                    HẠ TẦNG ENTERPRISE LAB 3 NODES                                  |
|                                                                                                    |
|  [Client] (172.28.41.20)                 [Router / Firewall]             [Web Server] (172.28.42.10)
|     │                                     (Gateway L3)                            │                |
|     │ eth0 (MTU 1500)             eth0 (LAN A)     eth1 (WAN/VPN - MTU 1400)      │ eth0 (MTU 1500)|
|     │                               172.28.41.254    172.28.42.254                │                |
|     └─────────────────────────────────────┘                └──────────────────────┘                |
|               Net-LAN-Client                                       Net-WAN-Server                  |
|          (Subnet: 172.28.41.0/24)                             (Subnet: 172.28.42.0/24)             |
+----------------------------------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành Nhanh

### Bước 1: Khởi động môi trường & Định tuyến ban đầu
```bash
cd com-them-router
docker compose up -d --build
./scripts/0-init.sh
```

---

### Bước 2: Thử nghiệm 3 Kịch Bản Thực Tế

#### 🔹 Kịch bản 1: Đường truyền MTU 1400 chuẩn (PMTUD hoạt động tốt)
Router hạ MTU interface `eth1` xuống `1400`, nhưng **cho phép ICMP** hoạt động bình thường:
```bash
./scripts/1-normal-pmtud.sh
./scripts/test.sh
```
* **Kết quả quan sát:**
  - `ping -s 1450 -M do` nhận được phản hồi: `From 172.28.41.254: Frag needed and DF set (mtu = 1400)`.
  - `curl` tải trang web thành công vì Server tự động giảm kích thước TCP segment xuống $\le 1360$ bytes sau khi nhận được ICMP từ Router.

---

#### 🔹 Kịch bản 2: Kích hoạt MTU Blackhole (Firewall trên Router chặn ICMP)
Firewall trên Router chặn gói `ICMP Fragmentation Needed`:
```bash
./scripts/2-fault-blackhole.sh
./scripts/test.sh
```
* **Hiện tượng lỗi:**
  - `ping` gói nhỏ (64B) qua mượt mà (0% loss).
  - `ping -s 1450 -M do` rớt `100%` (không có bất kỳ gói ICMP nào báo về $\rightarrow$ Blackhole!).
  - `curl` báo `HTTP 200` nhưng `tải về 0 bytes` (treo mãi mãi) do Server retransmit gói 1500B vô vọng.

---

#### 🔹 Kịch bản 3: Sửa lỗi chuẩn Enterprise bằng TCP MSS Clamping trên Router
Router kích hoạt tính năng **TCP MSS Clamping** trên chain `FORWARD`:
```bash
./scripts/3-fix-mss-clamping.sh
./scripts/test.sh
```
* **Kết quả:**
  - Không cần sửa cấu hình từng Client hay Server!
  - Router tự động viết lại trường `MSS = 1360` trong gói `TCP SYN / SYN-ACK` đi ngang qua.
  - `curl` tải về toàn bộ `3093 bytes` ngay lập tức!

---

### 🦈 Bắt Gói Tin Phân Tích Bằng Wireshark
Chạy script tự động capture trên Router:
```bash
./scripts/capture.sh
```
Mở file `router.pcap` trong Wireshark để quan sát:
1. Gói `TCP SYN` bị Router can thiệp sửa MSS option từ `1460` thành `1360`.
2. Gói `ICMP Type 3 Code 4` sinh ra khi Router gặp gói vượt MTU.
3. Các gói `[TCP Retransmission]` khi rơi vào Blackhole.

---

### 🧹 Dọn dẹp Lab
```bash
docker compose down
```
