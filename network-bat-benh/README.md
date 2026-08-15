# 🩺 Network Bắt Bệnh — Chẩn Đoán & Khắc Phục Sự Cố Mạng Thực Tế

<p align="center">
  <a href="https://www.youtube.com/@NetworkThucChien">
    <img src="https://img.shields.io/badge/YouTube-Network%20Thực%20Chiến-red?style=for-the-badge&logo=youtube" alt="YouTube Channel">
  </a>
  <a href="https://github.com/thangphan205/network-thuc-chien">
    <img src="https://img.shields.io/badge/Status-12%20Labs%20Ready-brightgreen?style=for-the-badge" alt="Status">
  </a>
  <img src="https://img.shields.io/badge/Format-1%20Tập%201%20Lỗi-blue?style=for-the-badge" alt="Format">
</p>

> **Triết lý series:** **1 Tập = 1 Ca Bệnh Thực Chiến Duy Nhất**.
> Bỏ qua lý thuyết trừu tượng và suy đoán mơ hồ — Kỹ sư mạng giỏi là một **Bác sĩ mạng**: Có quy trình khám bệnh khoa học, biết dùng công cụ xét nghiệm chính xác (Wireshark, tcpdump, ss, dig, iproute2) để bắt đúng **Nguyên nhân gốc rễ (Root Cause)** và kê đúng **Đơn thuốc xử lý**.

---

## 🧠 Quy Trình "Bắt Bệnh" Chuẩn 5 Bước (Troubleshooting Framework)

```
[1. Tiếp nhận bệnh án]  → Thu thập triệu chứng: Ai bị? Khi nào? Lỗi gì? Ứng dụng báo mã lỗi nào?
        ↓
[2. Bắt mạch phân tầng] → Kiểm tra từng tầng OSI từ L1 đến L7 để khoanh vùng điểm phân giới.
        ↓
[3. Xét nghiệm chuyên sâu] → Bắt gói tin (Wireshark / tcpdump), soi socket (`ss`), truy vấn DNS (`dig`).
        ↓
[4. Xác định căn nguyên] → Tìm ra Root Cause chính xác (Không chữa triệu chứng tạm thời).
        ↓
[5. Kê đơn & Phòng ngừa] → Sửa lỗi (Fix), kiểm thử lại, viết Post-mortem & bổ sung Monitoring/Alert.
```

> 📄 **Xem chi tiết sơ đồ tư duy & flowchart hoàn chỉnh:** [🧠 Sơ Đồ Tư Duy & Flowchart 5 Bước Bắt Bệnh](./quy-trinh-bat-benh.md)

---

## 📋 Danh Mục 12 Ca Bệnh Thực Chiến (Mỗi Tập 1 Lỗi)

| Tập | Mã Lỗi | Tên Ca Bệnh & Hiện Tượng | Tầng Mạng / Giao Thức | Tài Liệu & Thực Hành |
| :---: | :--- | :--- | :--- | :---: |
| **01** | `FW-DROP` | **Ping thông nhưng Web xoay tròn rồi Timeout** | L4 — TCP Port / Firewall Silent DROP | [📂 `tap-01-firewall-drop`](./tap-01-firewall-drop) |
| **02** | `FW-REJECT` | **Ping thông nhưng Web báo Connection Refused tức thì** | L4 — TCP RST / Active REJECT | [📂 `tap-02-firewall-reject`](./tap-02-firewall-reject) |
| **03** | `BIND-LOCAL` | **Đứng tại server vào được Web, máy khác cùng mạng thì không** | L4 — Socket Bind `127.0.0.1` vs `0.0.0.0` | [📂 `tap-03-bind-localhost`](./tap-03-bind-localhost) |
| **04** | `MTU-HOLE` | **Ping gói nhỏ OK, Web tải nửa chừng thì đơ (Treo trang)** | L3/L4 — Path MTU Discovery Blackhole | [📂 `tap-04-mtu-blackhole`](./tap-04-mtu-blackhole) |
| **05** | `ARP-STALE` | **Đổi IP máy chủ xong cả mạng nội bộ mất kết nối** | L2 — Stale ARP Cache / Gratuitous ARP | [📂 `tap-05-arp-stale-cache`](./tap-05-arp-stale-cache) |
| **06** | `DNS-CACHE` | **Truy cập IP được nhưng gõ Tên miền báo lỗi không tìm thấy** | L7 — DNS Resolver & `/etc/resolv.conf` | [📂 `tap-06-dns-resolution-failure`](./tap-06-dns-resolution-failure) |
| **07** | `TLS-CLOCK` | **Vào web HTTPS bị báo lỗi Chứng chỉ không hợp lệ** | L5/L6 — TLS Handshake & Clock Skew | [📂 `tap-07-tls-clock-skew`](./tap-07-tls-clock-skew) |
| **08** | `TLS-CHAIN` | **Máy tính vào web bình thường, điện thoại/curl báo lỗi SSL** | L5/L6 — Thiếu Intermediate CA Cert | [📂 `tap-08-tls-missing-intermediate-ca`](./tap-08-tls-missing-intermediate-ca) |
| **09** | `NAT-TIMEOUT` | **App đang dùng bình thường cứ sau 5 phút là bị ngắt kết nối** | L4 — NAT Session Idle Timeout | [📂 `tap-09-nat-session-timeout`](./tap-09-nat-session-timeout) |
| **10** | `ASYM-ROUTING` | **Ping 2 chiều thông suốt nhưng SSH/HTTP vừa vào là rớt** | L3 — Asymmetric Routing qua Stateful FW | [📂 `tap-10-asymmetric-routing`](./tap-10-asymmetric-routing) |
| **11** | `CONNTRACK-FULL` | **Server mạng mạnh nhưng thỉnh thoảng drop kết nối ngẫu nhiên** | Linux Kernel — Tràn bảng `nf_conntrack` | [📂 `tap-11-conntrack-table-full`](./tap-11-conntrack-table-full) |
| **12** | `GW-MISSING` | **Trong mạng LAN giao tiếp tốt, không ra được Internet** | L3 — Default Gateway & Subnet Mask | [📂 `tap-12-missing-default-gateway`](./tap-12-missing-default-gateway) |

---

## 🚀 Hướng Dẫn Thực Hành Nhanh Cho Học Viên

Mọi bài lab trong series này đều được đóng gói độc lập bằng **Docker Compose** và tương thích 100% với macOS, Linux, Windows:

```bash
# 1. Di chuyển vào thư mục bài lab bạn muốn học (Ví dụ Tập 01)
cd tap-01-firewall-drop

# 2. Khởi động môi trường lab
docker compose up -d

# 3. Kích hoạt lỗi để bắt đầu bắt bệnh
./scripts/1-fault.sh

# 4. Mở Wireshark trên máy tính (bắt card Loopback lo0 hoặc docker bridge) và chạy test
./scripts/test.sh

# 5. Chữa bệnh và khôi phục hệ thống
./scripts/2-cure.sh
```

---

## 🧭 Ma Trận Công Cụ Chẩn Đoán Theo Tầng OSI

| Tầng OSI | Câu Hỏi Khám Bệnh | Công Cụ Chẩn Đoán Tiêu Biểu |
| :--- | :--- | :--- |
| **L2 (Data Link)** | Địa chỉ MAC đích có đúng không? ARP có resolve không? | `ip neigh`, `arp -n`, `arping` |
| **L3 (Network)** | Route có đi đúng hướng không? MTU có bị nghẽn không? | `ping`, `mtr`, `ip route`, `traceroute` |
| **L4 (Transport)** | Cổng có mở không? Trạng thái Socket ra sao? Firewall chặn gì? | `ss -tulpn`, `nc -zvw`, `curl -Iv`, `iptables -L` |
| **L5-L6 (TLS/SSL)** | Chuỗi chứng chỉ có đủ không? Giờ hệ thống có chuẩn không? | `openssl s_client -showcerts`, `date`, `chronyc` |
| **L7 (Application)** | DNS trả về IP nào? Mã trạng thái HTTP trả về là gì? | `dig +trace`, `nslookup`, `curl -sI` |

---

*Theo dõi các video bài giảng chi tiết tại kênh YouTube [Network Thực Chiến](https://www.youtube.com/@NetworkThucChien).*
