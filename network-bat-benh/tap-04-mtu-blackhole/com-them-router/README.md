# 🔬 Lab Cơm Thêm: Mô Phỏng MTU Blackhole Đầy Đủ Qua Router / Firewall Trung Gian

> 💡 **Mục đích:** Lab nâng cao dành cho học viên muốn đào sâu thực tế hạ tầng Enterprise/Cloud — nơi Client và Server nằm ở 2 phân đoạn mạng riêng biệt và đi qua Router/Firewall trung gian (với MTU đường WAN bị bóp nhỏ do VPN/Tunnel).

---

## 🗺️ Sơ Đồ Kiến Trúc Mạng 3 Nodes

```text
   NET-CLIENT 172.28.41.0/24                                       NET-SERVER 172.28.42.0/24

   +---------------------+        +-----------------------+        +----------------------+
   |        Client       |        |   Router / Firewall   |        |      Web Server      |
   |     172.28.41.20    |--------|   eth0 172.28.41.254  |--------|     172.28.42.10     |
   |    eth0  MTU 1500   |        |   eth1 172.28.42.254  |        |    eth0  MTU 1500    |
   +---------------------+        +-----------------------+        +----------------------+
                           LAN                              WAN / VPN  MTU 1400

   Router: ip_forward=1  |  route ... mtu 1400  |  mangle FORWARD MSS clamp -> 1360
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
Router đặt **route MTU 1400** trên cả hai chân (link MTU vẫn giữ 1500), và **cho phép ICMP** đi thông suốt:
```bash
./scripts/1-normal-pmtud.sh
./scripts/test.sh
```
* **Kết quả quan sát:** — có **hai** lượt PMTUD ngược chiều nhau, đừng nhầm:
  - `ping -s 1450 -M do`: Client là nguồn gói quá khổ → Router trả ICMP **về Client**:
    `From 172.28.41.254: Frag needed and DF set (mtu = 1400)`.
  - `curl`: Web Server là nguồn gói body 1500B → Router trả ICMP **về Server** (`172.28.42.254 > 172.28.42.10`), Server tự hạ segment xuống 1360 byte và trang web tải đủ `3093 bytes`.
  - ⚠️ Muốn thấy lượt thứ hai, PMTU cache trên Client phải sạch — xem mục [PMTU Cache](#-ghi-chú-bắt-buộc-đọc-pmtu-cache-trên-client--server).

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

### 🧹 Ghi Chú Bắt Buộc Đọc: PMTU Cache Trên Client / Server

Sau khi nhận `ICMP Type 3 Code 4`, Linux **không chỉ sửa kết nối đang chạy** — nó ghi luôn PMTU vào *route exception* của host, mặc định giữ **10 phút**:

```bash
docker compose exec client ip route get 172.28.42.10
# 172.28.42.10 via 172.28.41.254 dev eth0 src 172.28.41.20 uid 0
#     cache expires 523sec mtu 1400          <-- da hoc duoc PMTU
```

**Hậu quả khi demo:** `test.sh` bắn `ping -s 1450 -M do` (TEST 2) trước khi `curl` (TEST 3). Ping làm Client học PMTU 1400, nên tới TEST 3 Client mở kết nối với `MSS=1360` **ngay từ gói SYN** — không gói nào vượt 1400, Router **không phải sinh ICMP nào cả**. Toàn bộ màn PMTUD phía Server biến mất khỏi bản capture:

```
# Cache CON, khong co ICMP:
eth0 In  IP 172.28.41.20 > 172.28.42.10: Flags [S], options [mss 1360, ...]
eth1 In  IP 172.28.42.10 > 172.28.41.20: length 1348      <- vua khit, khong ai bi drop

# Cache SACH, ICMP hien ra:
eth0 In  IP 172.28.41.20 > 172.28.42.10: Flags [S], options [mss 1460, ...]
eth1 In  IP 172.28.42.10 > 172.28.41.20: length 1448      <- goi 1500B IP, DF=1
eth1 Out IP 172.28.42.254 > 172.28.42.10: ICMP need to frag (mtu 1400)
eth1 In  IP 172.28.42.10 > 172.28.41.20: length 1348      <- Server tu ha xuong 1400B
```

`test.sh` đã tự xoá cache trước TEST 3. Nếu chạy tay thì xoá thủ công:

```bash
# Xoa PMTU cache tren Client (huong Client -> Server)
docker compose exec client ip route del 172.28.42.0/24
docker compose exec client ip route add 172.28.42.0/24 via 172.28.41.254

# Xoa PMTU cache tren Server (huong Server -> Client)
docker compose exec web-server ip route del 172.28.41.0/24
docker compose exec web-server ip route add 172.28.41.0/24 via 172.28.42.254

# Kiem tra lai: dong 'cache' phai TRONG, khong con 'mtu 1400'
docker compose exec client ip route get 172.28.42.10
```

> ⚠️ `ip route flush cache` **không dùng được** trong container — `/proc/sys/net/ipv4/route/flush` là read-only. Phải xoá rồi thêm lại route như trên.

**Router gửi ICMP cho ai?** Luôn gửi ngược về **nguồn của gói quá khổ**, source IP là interface Router *nhận* gói (RFC 1191):

| Gói quá khổ do ai gửi | Router trả ICMP về | Source IP của ICMP |
|---|---|---|
| Client (`ping -s 1450 -M do`) | **Client** `172.28.41.20` | `172.28.41.254` (eth0) |
| Web Server (body HTTP 1500B) | **Web Server** `172.28.42.10` | `172.28.42.254` (eth1) |

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
