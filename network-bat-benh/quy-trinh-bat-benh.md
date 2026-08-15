# 🧠 Sơ Đồ Tư Duy: Quy Trình 5 Bước "Bắt Bệnh" Network Thực Chiến

> **Triết lý:** Một kỹ sư mạng giỏi không bao giờ đoán mò. Họ có phương pháp, có tư duy của một bác sĩ và biết hỏi đúng câu hỏi ở đúng tầng OSI.

---

<p align="center">
  <img src="./images/quy-trinh-bat-benh.jpg" alt="Quy Trình 5 Bước Bắt Bệnh Network" width="100%">
</p>

---

## 🗺️ 1. Sơ Đồ Tư Duy Tổng Thể (Mindmap)

```mermaid
mindmap
  root((🩺 5 BƯỚC BẮT BỆNH NETWORK))
    ["1. Tiếp Nhận Bệnh Án"]
      ["Ghi nhận triệu chứng 5W1H"]
        ["Ai bị? Khi nào? Mã lỗi gì?"]
      ["Khoanh vùng phạm vi"]
        ["1 máy hay toàn mạng LAN / WAN?"]
      ["Tái hiện lỗi - Reproduce"]
        ["Test thực tế từ Client & Server"]
    ["2. Bắt Mạch Phân Tầng (Divide & Conquer)"]
      ["MỐC 1: Bắt Mạch L3 (Ping IP)"]
        ["Ping THẤT BẠI -> Soi L1/L2/L3 (Cáp, ARP, Route, MTU)"]
        ["Ping THÀNH CÔNG -> Loại trừ L1-L3, soi tiếp L4-L7"]
      ["MỐC 2: Bắt Mạch L4 (TCP Port)"]
        ["Treo Timeout -> Firewall DROP, Asymmetric Route"]
        ["Connection Refused -> Bind 127.0.0.1, Service chết"]
      ["MỐC 3: Bắt Mạch L7 (DNS Resolution)"]
        ["Ping IP được, gõ domain chết -> Lỗi DNS / /etc/resolv.conf"]
      ["MỐC 4: Bắt Mạch L5-L6 (TLS Handshake)"]
        ["Lỗi Chứng chỉ -> Lệch giờ Clock Skew, Thiếu Intermediate CA"]
    ["3. Xét Nghiệm Chuyên Sâu"]
      ["Soi đáy gói tin: Wireshark & tcpdump"]
        ["Tìm cờ: SYN Retransmission, RST, ICMP Type 3"]
      ["Soi Kernel & Network Stack"]
        ["dmesg | grep conntrack (Tràn bảng conntrack)"]
        ["sysctl / ss (Tràn SYN Backlog Queue)"]
    ["4. Xác Định Căn Nguyên"]
      ["Khám nghiệm bằng chứng"]
        ["Dựa trên Packet và Log - Không đoán mò"]
      ["Chốt Root Cause chính xác"]
    ["5. Kê Đơn & Phòng Ngừa"]
      ["Kê đơn xử lý - Fix"]
        ["Mở Firewall / MSS Clamping / Fullchain Cert / Sửa Route"]
      ["Tái khám - Verification"]
        ["Chạy test kiểm chứng HTTP 200 OK"]
      ["Phòng ngừa tái phát"]
        ["Viết Post-mortem tài liệu hóa"]
        ["Thiết lập Prometheus Monitoring & Alerting"]
```

---

## 🧭 2. Cây Quyết Định Bắt Mạch Bước 2 (Divide & Conquer Decision Tree)

Chiến lược thông minh nhất trong Bước 2 là **Chia để trị (Divide & Conquer)** — Lấy **Tầng 3 (Ping IP)** làm ranh giới để cắt đôi không gian tìm kiếm, không test mò mẫm từ L1:

```mermaid
flowchart TD
    START["🚨 BẮT ĐẦU BẮT MẠCH BƯỚC 2"] --> Q1{"1. Ping IP máy chủ có phản hồi không?<br><code>ping &lt;IP&gt;</code>"}

    %% NHÁNH PING THẤT BẠI (LỖI NỬA DƯỚI: L1 - L3)
    Q1 -->|"❌ KHÔNG (Rớt gói)"| L1_CHECK{"Kiểm tra Card mạng (L1)?<br><code>ip link</code>"}
    L1_CHECK -->|"Link DOWN"| FIX_L1["🔴 L1: Cáp lỏng / NIC chưa bật / Port Disable"]
    L1_CHECK -->|"Link UP"| L2_CHECK{"Kiểm tra bảng ARP (L2)?<br><code>ip neigh show</code>"}
    
    L2_CHECK -->|"Sai MAC / Incomplete"| FIX_L2["🔴 L2: Stale ARP Cache / Trùng MAC"]
    L2_CHECK -->|"MAC đúng"| L3_CHECK{"Kiểm tra Định tuyến (L3)?<br><code>ip route show</code>"}
    
    L3_CHECK -->|"Mất Default Route"| FIX_L3_GW["🔴 L3: Thiếu Default Gateway / Sai Subnet"]
    L3_CHECK -->|"Route đúng"| FIX_L3_MTU["🔴 L3: MTU Blackhole (Test: <code>ping -s 1472 -M do</code>)"]

    %% NHÁNH PING THÀNH CÔNG (L1-L3 ĐÃ THÔNG, LỖI NỬA TRÊN: L4 - L7)
    Q1 -->|"✅ CÓ (L1-L3 Thông suốt)"| Q2{"2. Cổng TCP (L4) có kết nối được không?<br><code>nc -zvw &lt;IP&gt; &lt;Port&gt;</code>"}
    
    Q2 -->|"❌ Treo Timeout (5s-30s)"| FIX_L4_DROP["🟠 L4: Firewall Silent DROP / Asymmetric Routing / NAT Timeout"]
    Q2 -->|"❌ Báo Connection Refused"| Q2_BIND{"Kiểm tra Socket trên Server?<br><code>ss -tulpn</code>"}
    
    Q2_BIND -->|"Bind 127.0.0.1"| FIX_L4_BIND["🟠 L4: Web Server bind nhầm localhost thay vì 0.0.0.0"]
    Q2_BIND -->|"Service không chạy"| FIX_L4_DOWN["🟠 L4: Ứng dụng bị Crash / Chưa khởi động"]
    
    Q2 -->|"✅ CÓ (TCP Handshake OK)"| Q3{"3. Phân giải Tên miền (L7 DNS) có ra IP?<br><code>dig +short &lt;domain&gt;</code>"}
    
    Q3 -->|"❌ DNS Timeout / NXDOMAIN"| FIX_L7_DNS["🟡 L7: Sai DNS Server / /etc/resolv.conf hỏng"]
    Q3 -->|"✅ CÓ (DNS Resolve đúng)"| Q4{"4. Bắt tay TLS/HTTPS (L5/L6) có thông?<br><code>openssl s_client</code>"}
    
    Q4 -->|"❌ Lỗi Cert Expired / Date"| FIX_TLS_CLOCK["🔵 L5/L6: Lệch giờ hệ thống (Clock Skew)"]
    Q4 -->|"❌ Lỗi Unable to get local issuer"| FIX_TLS_CHAIN["🔵 L5/L6: Thiếu Intermediate CA Certificate"]
    Q4 -->|"✅ CÓ (TLS Handshake 200 OK)"| FIX_APP["🟢 L7: Lỗi logic Backend Application (HTTP 500 / 502 / 403)"]

    style START fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#fff
    style FIX_L1 fill:#7f1d1d,stroke:#ef4444,color:#fff
    style FIX_L2 fill:#7f1d1d,stroke:#ef4444,color:#fff
    style FIX_L3_GW fill:#7f1d1d,stroke:#ef4444,color:#fff
    style FIX_L3_MTU fill:#7f1d1d,stroke:#ef4444,color:#fff
    style FIX_L4_DROP fill:#7c2d12,stroke:#f97316,color:#fff
    style FIX_L4_BIND fill:#7c2d12,stroke:#f97316,color:#fff
    style FIX_L4_DOWN fill:#7c2d12,stroke:#f97316,color:#fff
    style FIX_L7_DNS fill:#713f12,stroke:#eab308,color:#fff
    style FIX_TLS_CLOCK fill:#1e3a5f,stroke:#3b82f6,color:#fff
    style FIX_TLS_CHAIN fill:#1e3a5f,stroke:#3b82f6,color:#fff
    style FIX_APP fill:#064e3b,stroke:#10b981,color:#fff
```

---

## 📋 3. Chi Tiết Các Trạm Khám Ở Bước 2 (Cheat Sheet Từng Tầng)

| Trạm Khám | Tầng OSI | Câu Hỏi Khám Bệnh | Câu Lệnh Bắt Mạch Nhanh | Dấu Hiệu Lỗi Thường Thấy |
| :--- | :--- | :--- | :--- | :--- |
| **Trạm 1: Vật lý** | **L1 — Physical** | *Card mạng có UP không? Có nhận link không?* | `ip link show`, `ethtool eth0` | `state DOWN`, `NO-CARRIER` (Cáp lỏng, driver lỗi) |
| **Trạm 2: Data Link** | **L2 — Data Link** | *Bảng ARP có học đúng địa chỉ MAC không?* | `ip neigh show`, `arping -I eth0 <IP>` | `FAILED`, `INCOMPLETE`, hoặc lưu địa chỉ MAC cũ |
| **Trạm 3: Định tuyến** | **L3 — Network** | *Ping IP có tới không? Có Default Route không?* | `ping -c 3 <IP>`, `ip route show` | `Network is unreachable`, `Destination Host Unreachable` |
| **Trạm 4: Kích thước gói** | **L3 — MTU** | *Gói tin to có bị rơi vào hố đen không?* | `ping -s 1472 -M do <IP>` | Ping nhỏ thông 100%, ping to mất gói 100% (MTU Blackhole) |
| **Trạm 5: Cổng dịch vụ** | **L4 — Transport** | *Cổng có mở không? Trạng thái kết nối ra sao?* | `nc -zvw3 <IP> <Port>`, `curl -Iv <URL>` | • `Connection timed out` (Firewall DROP)<br>• `Connection refused` (Port đóng / Bind 127.0.0.1) |
| **Trạm 6: Socket Server** | **L4 — Socket** | *Server bind trên IP nào?* | `ss -tulpn \| grep :<Port>` | `127.0.0.1:80` (Sai — Chỉ cho nội bộ) thay vì `0.0.0.0:80` |
| **Trạm 7: Tên miền** | **L7 — DNS** | *Domain có phân giải ra đúng IP không?* | `dig +short <Domain> @8.8.8.8`, `cat /etc/resolv.conf` | `Could not resolve host`, `NXDOMAIN`, `SERVFAIL` |
| **Trạm 8: Bảo mật TLS** | **L5/L6 — TLS** | *Chứng chỉ có đủ chuỗi và đúng ngày giờ không?* | `openssl s_client -connect <Host>:443 -showcerts` | `certificate has expired` (Sai giờ), `unable to get local issuer` (Thiếu Intermediate CA) |

---

## 🔬 4. Tổng Kết: 5 Bước Bắt Bệnh Network

```
[BƯỚC 1: TIẾP NHẬN]   → Thu thập triệu chứng 5W1H (Treo xoay vòng vs Báo lỗi tức thì vs Chập chờn).
         ↓
[BƯỚC 2: BẮT MẠCH]    → Dùng chiến lược Divide & Conquer (Ping L3 làm mốc) để khoanh vùng đúng tầng lỗi.
         ↓
[BƯỚC 3: XÉT NGHIỆM]  → Mở Wireshark / tcpdump soi cờ (SYN, RST, Retransmission) và soi dmesg Kernel.
         ↓
[BƯỚC 4: BẮT BỆNH]    → Xác định chính xác 1 trong 12 Root Cause (Không suy đoán mò mẫm).
         ↓
[BƯỚC 5: KÊ ĐƠN]      → Fix lỗi dứt điểm, kiểm thử lại 200 OK và viết tài liệu Post-mortem phòng ngừa.
```

---

*Kho tài liệu đồng hành cùng kênh [Network Thực Chiến](https://www.youtube.com/@NetworkThucChien).*
