# 💡 Cơm Thêm: Giải Phẫu MTU Blackhole Qua Phân Đoạn Router / Firewall Thực Tế

> Tài liệu bổ trợ chuyên sâu cho **Tập 04: Path MTU Blackhole**.

---

## 1. Bức Tranh Hạ Tầng Thực Tế vs Mô Hình Lab Cơ Bản

Trong lab cơ bản của Tập 04, chúng ta dùng mô hình **2 containers** (Client & Web Server chung mạng phẳng L2) và dùng luật `iptables` tại Client để tái hiện triệu chứng nhanh trong 5 phút.

Tuy nhiên, trong các mạng doanh nghiệp, ISP, VPN Site-to-Site hoặc hạ tầng Cloud (AWS, Azure, GCP, Kubernetes Overlay), **MTU Blackhole hầu như luôn xảy ra ở các thiết bị Router/Firewall trung gian**.

```text
[Client LAN] --(MTU 1500)--> [Edge Router] --(MTU 1400: IPsec/GRE/VXLAN)--> [Firewall] --(MTU 1500)--> [Web Server]
                                                          ^
                                          Chỗ thắt nút MTU & điểm chặn ICMP
```

---

## 2. Ba Tình Huống Kinh Điển Tại Phân Đoạn Router / Firewall

### 🔹 Tình huống 1: Đường truyền MTU thấp nhưng "Khỏe mạnh" (PMTUD Chuẩn)

Khi Router trung gian kết nối một đường hầm VPN có `MTU = 1400` và **không có Firewall nào chặn ICMP**:

```text
   Client 172.28.41.20              Router  MTU 1400                    Web Server 172.28.42.10
      |                                     |                                       |
      | --- 1. TCP SYN (MSS=1460) --------->| ------------------------------------->|
      |<--- 2. TCP SYN,ACK (MSS=1460) ------|<--------------------------------------|
      | --- 3. TCP ACK -------------------->| ------------------------------------->|
      | --- 4. HTTP GET / ----------------->| ------------------------------------->|
      |                                     |                                       |
      |                                     |<--- 5. Data Segment (1500B, DF=1) ----|   vượt MTU 1400 của Router
      |                                     |                                       |
      |                                     | --- 6. ICMP Type 3 Code 4 ----------->|   Frag Needed, next-hop MTU=1400
      |                                     |                                       |   Server tự hạ PMTU xuống 1400
      |                                     |                                       |
      |<--- 7. Data Segment (1400B) --------|<--- 8. Data (1400B) ------------------|
      v                                     v                                       v

   => Kết nối thành công, web tải trọn vẹn dù đường truyền bị thắt nút.
```

👉 **Cơ chế:** Gói dữ liệu đầu tiên bị rớt, nhưng Server nhận được `ICMP Type 3 Code 4` $\rightarrow$ Server tự động phân mảnh hoặc giảm kích thước các segment tiếp theo $\rightarrow$ Web vẫn tải bình thường.

---

### 🔹 Tình huống 2: Căn Bệnh "MTU Blackhole" Thực Sự Ra Đời (Do Firewall Chặn ICMP)

Nhiều quản trị viên mạng cấu hình chính sách bảo mật Firewall theo kiểu cực đoan: **"Drop All ICMP"** để tránh bị ping quét mạng (Reconnaissance Attack). 

Hậu quả là gói tin **ICMP Type 3 Code 4 cũng bị giết chết**:

```text
   Client 172.28.41.20              Router  MTU 1400                    Web Server 172.28.42.10
      |                                     |                                       |
      | --- 1. TCP handshake + HTTP GET --->| ------------------------------------->|
      |                                     |                                       |
      |                                     |<--- 2. Data Segment (1500B, DF=1) ----|   vượt MTU 1400 -> DROP
      |                                     |                                       |
      |                                     | --- 3. ICMP Frag Needed -------------X|   bị firewall DROP ngay tại Router
      |                                     |                                       |   Server không nhận được gì,
      |                                     |                                       |   tưởng gói rớt ngẫu nhiên
      |                                     |                                       |
      |                                     |<--- 4. Retransmit 1500B (0.2s) -------|   lại vượt MTU -> DROP
      |                                     |<--- 5. Retransmit 1500B (0.4s) -------|   lại DROP
      |                                     |<--- 6. Retransmit 1500B (0.8s) -------|   lại DROP
      v                                     v                                       v

   => MTU BLACKHOLE: curl báo HTTP 200 nhưng tải 0 bytes, treo mãi mãi.
```

---

### 🔹 Tình huống 3: Giải Pháp Chuẩn Enterprise — TCP MSS Clamping Trên Router

Trong thực tế, bạn không thể ép tất cả Firewall trên Internet mở ICMP, cũng không thể đi cấu hình từng máy Client/Server. 

Giải pháp tối ưu nhất là cấu hình **TCP MSS Clamping ngay trên Gateway / Router trung gian**:

```text
   Client 172.28.41.20              Router  MSS clamp                   Web Server 172.28.42.10
      |                                     |                                       |
      | --- 1. TCP SYN (MSS=1460) --------->|                                       |
      |                                     |                                       |   Router sửa MSS: 1460 -> 1360
      |                                     | --- 2. TCP SYN (MSS=1360) ----------->|
      |                                     |                                       |
      |                                     |<--- 3. TCP SYN,ACK (MSS=1460) --------|
      |                                     |                                       |   Router sửa MSS: 1460 -> 1360
      |<--- 4. TCP SYN,ACK (MSS=1360) ------|                                       |
      |                                     |                                       |   Hai đầu đều tin phía kia chỉ
      |                                     |                                       |   nhận tối đa segment 1360 byte
      |                                     |                                       |
      | --- 5. HTTP GET / ----------------->| ------------------------------------->|
      |<--- 6. Data (Segment 1360B) --------|<--- 7. Data (1360B) ------------------|
      v                                     v                                       v

   => Web tải tốc độ tối đa ngay từ gói đầu tiên, không cần PMTUD.
```

---

## 3. Bảng Cấu Hình TCP MSS Clamping Trên Các Thiết Bị Thực Tế

| Thiết bị / Nền tảng | Lệnh cấu hình MSS Clamping |
| :--- | :--- |
| **Linux Router (iptables)** | `iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu` |
| **Linux Router (nftables)** | `nft add rule ip filter forward tcp flags syn tcp option maxseg size set rt mtu` |
| **Cisco IOS / IOS-XE** | `interface GigabitEthernet0/1`<br>` ip tcp adjust-mss 1360` |
| **Mikrotik RouterOS** | `/ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss new-mss=clamp-to-pmtu` |
| **Fortinet FortiGate** | `config system interface`<br>` edit "wan1"`<br>` set tcp-mss 1360`<br>`next`<br>`end` |
| **pfSense / OPNsense** | `Interfaces` $\rightarrow$ `WAN` $\rightarrow$ `MSS: 1360` (hoặc bật System Tunables `net.inet.tcp.mssdflt`) |

---

## 4. Thực Hành Ngay Với Lab 3 Nodes (`com-them-router`)

Mã nguồn và script thực hành đầy đủ cho mô hình 3 Nodes đã được tạo sẵn tại thư mục:
📂 [`com-them-router/`](./com-them-router)

```bash
# 1. Di chuyển vào thư mục lab router
cd com-them-router

# 2. Khởi động và thiết lập định tuyến
docker compose up -d --build
./scripts/0-init.sh

# 3. Chạy từng kịch bản để trải nghiệm:
./scripts/1-normal-pmtud.sh      # Thấy PMTUD và ICMP Type 3 Code 4
./scripts/2-fault-blackhole.sh   # Thấy MTU Blackhole thật sự
./scripts/3-fix-mss-clamping.sh  # Sửa bằng MSS Clamping trên Router

# 4. Kiểm tra kết quả
./scripts/test.sh

# 5. Bắt gói tin phân tích trên Router
./scripts/capture.sh
```
