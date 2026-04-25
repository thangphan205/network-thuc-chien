# 🏓 ping — Không chỉ là "Có mạng không?"

`ping` là công cụ đầu tiên mọi người học, nhưng cũng là công cụ mà hầu hết chỉ dùng 10% khả năng thực sự của nó. Bài này khai thác phần 90% còn lại.

---

## ⚙️ Cơ chế hoạt động

`ping` gửi gói tin **ICMP Echo Request** (Type 8) và chờ **ICMP Echo Reply** (Type 0) từ đích.

```
Máy bạn                              Đích (google.com)
    │                                        │
    │──── ICMP Echo Request (Type 8) ───────►│
    │         [seq=1, TTL=64, size=64B]       │
    │                                        │
    │◄─── ICMP Echo Reply   (Type 0) ────────│
    │         [seq=1, TTL=118, time=12ms]     │
```

**Các thông số đọc từ output:**
- `time=` → RTT (Round Trip Time) tính bằng ms
- `TTL=` → Giá trị TTL còn lại sau khi qua các hop
- `icmp_seq=` → Số thứ tự gói — phát hiện gói bị mất nếu số nhảy cóc

---

## 🔬 Deep Dive: Cấu trúc gói tin ICMP

ICMP (Internet Control Message Protocol) là giao thức **điều khiển và thông báo lỗi** của tầng Network (L3), được định nghĩa trong [RFC 792](https://datatracker.ietf.org/doc/html/rfc792). `ping` chỉ là một ứng dụng nhỏ dùng 2 trong số hơn 40 loại message của ICMP.

### Cấu trúc header ICMP

```
 0               1               2               3
 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|     Type      |     Code      |           Checksum            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Identifier           |        Sequence Number        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
|                    Data (tùy ý, không giới hạn)              |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

| Trường | Kích thước | Ý nghĩa |
| :--- | :--- | :--- |
| **Type** | 1 byte | Loại ICMP message (xem bảng bên dưới) |
| **Code** | 1 byte | Chi tiết hơn trong từng Type |
| **Checksum** | 2 bytes | Kiểm tra tính toàn vẹn của header + data |
| **Identifier** | 2 bytes | ID phiên ping — khớp Request với Reply |
| **Sequence Number** | 2 bytes | Số thứ tự gói (`icmp_seq` trong output) |
| **Data** | Tùy ý | Payload — mặc định là pattern lặp lại, nhưng **có thể chứa bất cứ thứ gì** |

### Các ICMP Type quan trọng nhất

| Type | Code | Tên | Khi nào gặp |
| :--- | :--- | :--- | :--- |
| **0** | 0 | Echo Reply | Phản hồi của ping |
| **3** | 0 | Destination Net Unreachable | Route không tồn tại |
| **3** | 1 | Destination Host Unreachable | Host không reach được |
| **3** | 3 | Destination Port Unreachable | Port đóng (UDP) |
| **3** | 4 | Fragmentation Needed (DF set) | Gói quá lớn, cần phân mảnh nhưng DF=1 — **dấu hiệu MTU mismatch** |
| **8** | 0 | Echo Request | Gói ping gửi đi |
| **11** | 0 | TTL Exceeded in Transit | TTL về 0 — **traceroute/mtr dùng điều này** |
| **11** | 1 | Fragment Reassembly Timeout | Gói bị phân mảnh không reassemble được |

> **Liên kết thực chiến:** Khi `ping` báo "Frag needed" → đó là ICMP Type 3 Code 4. Khi `mtr` thấy từng hop → đó là ICMP Type 11 Code 0 được sinh ra khi TTL = 0 tại mỗi router.

### Payload mặc định của ping

Khi chạy `ping google.com`, payload 56 bytes là pattern lặp lại có thể dự đoán:
```
Data: 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f
      20 21 22 23 24 25 26 27 28 29 2a 2b 2c 2d 2e 2f
      30 31 32 33 34 35 36 37 ...
```
Pattern này **có thể thấy rõ trong Wireshark** ở phần ICMP Data. Khi payload **không** có pattern này → dấu hiệu đáng ngờ.

---

## 🚨 ICMP Tunneling — Khi ping trở thành kênh bí mật

*(Tham khảo: [Wireshark 4.2 - Thực chiến ICMP Tunneling](https://www.youtube.com/watch?v=6cC5YhD7gGA))*

### Ý tưởng cốt lõi

Trường **Data** trong ICMP Echo Request/Reply **không được kiểm soát bởi giao thức** — nó có thể chứa bất kỳ dữ liệu nào. Hầu hết firewall cho phép ICMP đi qua mà không kiểm tra payload. Đây là điều mà ICMP Tunneling khai thác:

```
Gói ICMP bình thường:
┌────────────────────────────────────────────────┐
│ IP Header │ ICMP Header │ Data: 10 11 12 13...  │  ← Payload vô nghĩa
└────────────────────────────────────────────────┘

Gói ICMP Tunneling:
┌───────────────────────────────────────────────────────────────┐
│ IP Header │ ICMP Header │ Data: [TCP/SSH/HTTP packet nhúng vào] │  ← Traffic thật!
└───────────────────────────────────────────────────────────────┘
```

### Cơ chế hoạt động

```
Mạng bị hạn chế (chỉ cho ICMP)         Internet tự do
     │                                        │
  [Client]──── ICMP Request ────────────►[Relay Server]
     │         [Data: GET /index.html]        │──► HTTP → Web Server
     │                                        │
  [Client]◄─── ICMP Reply ─────────────── [Relay Server]
               [Data: 200 OK <html>...]
```

### Công cụ ICMP Tunneling phổ biến

| Công cụ | Mô tả | Dấu hiệu đặc trưng |
| :--- | :--- | :--- |
| **ptunnel-ng** | Tunnel TCP qua ICMP, có auth | Payload size cố định lớn (1024B+) |
| **icmptunnel** | Tunnel IP-in-ICMP | Gói ICMP chứa IP header nhúng bên trong |
| **hans** | VPN qua ICMP Echo | Tần suất cao, payload encrypted |
| **nping** (nmap) | Tạo custom ICMP packet | Payload tùy chỉnh hoàn toàn |

### Phát hiện ICMP Tunneling

**Dấu hiệu bất thường khi nhìn bằng mắt:**

| Chỉ số | Ping bình thường | ICMP Tunneling |
| :--- | :--- | :--- |
| **Payload size** | 56-64 bytes | Lớn và bất thường (200B - 64KB) |
| **Tần suất** | 1 gói/giây | Liên tục, hàng trăm gói/giây |
| **Payload pattern** | Lặp lại có thể đoán | Random / encrypted (entropy cao) |
| **Identifier** | Tăng dần theo process | Cố định hoặc random |
| **Chiều traffic** | Request ≈ Reply size | Request ≠ Reply size (data bất đối xứng) |

**Phát hiện với tcpdump:**
```bash
# Bắt tất cả ICMP và hiển thị payload
sudo tcpdump -nn -i any icmp -X

# Lọc ICMP payload lớn bất thường (> 100 bytes)
sudo tcpdump -nn "icmp and greater 150"

# Đếm tần suất ICMP theo src IP
sudo tcpdump -nn icmp | awk '{print $3}' | cut -d. -f1-4 | sort | uniq -c | sort -rn
```

**Phát hiện với Wireshark:**
```
# Filter chỉ ICMP
icmp

# ICMP với payload lớn bất thường
icmp && frame.len > 150

# ICMP không phải Type 0 hoặc 8 (Echo)
icmp && !(icmp.type == 0 || icmp.type == 8)

# So sánh entropy của payload: Analyze → Expert Information
# Payload encrypted → entropy gần 8.0 (random hoàn toàn)
# Payload bình thường → entropy thấp hơn (pattern lặp lại)
```

**Script phát hiện tự động:**
```bash
#!/bin/bash
# Cảnh báo khi có ICMP payload lớn bất thường
sudo tcpdump -nn -i any "icmp and greater 150" -l 2>/dev/null | while read line; do
    echo "[ALERT $(date)] Suspicious ICMP: $line"
done
```

### Bypass và phòng thủ

**Tấn công:**
- Nhiều tường lửa doanh nghiệp, captive portal, public WiFi cho phép ICMP tự do
- ICMP Tunneling = bypass hoàn toàn các hạn chế TCP/UDP
- Traffic được mã hóa → khó detect bằng deep packet inspection đơn giản

**Phòng thủ:**
```bash
# 1. Rate-limit ICMP (Linux iptables)
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 10/s -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# 2. Giới hạn ICMP payload size (nftables)
nft add rule inet filter input ip protocol icmp icmp type echo-request \
    ip length > 100 drop

# 3. Block ICMP hoàn toàn nếu không cần thiết
iptables -A INPUT -p icmp -j DROP
```

> **Lưu ý bảo mật:** ICMP Tunneling là kỹ thuật thường dùng trong **APT (Advanced Persistent Threat)** để duy trì kênh C2 (Command & Control) qua các mạng có kiểm soát nghiêm ngặt. Hiểu cách nó hoạt động giúp xây dựng detection rule chính xác hơn.

---

## 🔢 TTL Fingerprinting — Đoán OS của đích

Mỗi hệ điều hành có giá trị TTL mặc định khác nhau khi **gửi đi**. Quan sát TTL nhận về, cộng ngược với số hop đã đi qua → suy ra TTL gốc → suy ra OS.

| TTL nhận về | Tính toán | Kết luận |
| :--- | :--- | :--- |
| 64 | 64 - 0 hop = 64 | Linux/macOS, cùng mạng |
| 63 | 64 - 1 hop = 64 | Linux/macOS, qua 1 router |
| 118 | 128 - 10 hop = 128 | Windows Server |
| 245 | 255 - 10 hop = 255 | Cisco router, thiết bị mạng |

```bash
ping google.com
# PING google.com: 56 data bytes
# 64 bytes from 142.250.196.46: icmp_seq=0 ttl=118 time=12.4 ms
#                                               ^^^^^^
# TTL=118 → Windows gửi TTL=128, đã đi qua 10 hop
```

> **Ứng dụng thực chiến:** Khi troubleshoot, biết OS của thiết bị trung gian giúp đặt đúng giả thuyết về cấu hình, firewall rule, và MTU mặc định.

---

## 📏 MTU Discovery — Kỹ năng must-have khi debug VPN/Tunnel

**MTU (Maximum Transmission Unit)** là kích thước tối đa của một gói tin trên đường truyền. Ethernet tiêu chuẩn = **1500 bytes**.

Khi qua VPN, GRE tunnel, hoặc VXLAN, MTU bị giảm do overhead của header đóng gói. Nếu gói tin quá lớn và không được phân mảnh → **TCP bị chậm bí ẩn, UDP bị drop**.

### Cách tính kích thước payload cho ping:
```
MTU (1500) - IP header (20) - ICMP header (8) = 1472 bytes (payload tối đa)
```

### Tìm MTU thực tế của đường truyền:

**Linux:**
```bash
# -s: payload size, -M do: đặt DF bit (Don't Fragment) — gói không được phép phân mảnh
ping -s 1472 -M do 192.168.1.1

# Nếu thành công → MTU >= 1500 ✅
# Nếu trả về "Frag needed and DF set" hoặc timeout → MTU < 1500 ❌

# Binary search để tìm chính xác:
ping -s 1400 -M do 192.168.1.1   # Thử 1400
ping -s 1450 -M do 192.168.1.1   # Thử 1450
ping -s 1440 -M do 192.168.1.1   # Thu hẹp dần...
```

**macOS:**
```bash
# macOS dùng -D thay vì -M do
ping -s 1472 -D 192.168.1.1
```

### Ví dụ thực tế — Debug TCP chậm qua VPN:
```bash
# Trong VPN, overhead WireGuard = 60 bytes
# MTU thực tế = 1500 - 60 = 1440

ping -s 1412 -M do 10.0.0.1   # 1440 - 20 (IP) - 8 (ICMP) = 1412 ← thành công
ping -s 1413 -M do 10.0.0.1   # ← bắt đầu fail

# Kết luận: MTU thực tế = 1440, cần set MSS clamp về 1400 cho TCP
```

---

## 📖 Cheatsheet — Các cờ quan trọng

### 1. Giới hạn số gói tin (không ping vô tận)
```bash
ping -c 10 google.com
# Gửi đúng 10 gói rồi dừng, in summary
```

### 2. Thay đổi tần suất gửi
```bash
# Mặc định: 1 gói/giây
ping -i 0.2 google.com   # 5 gói/giây (cần root nếu < 0.2s)

sudo ping -i 0.05 google.com  # 20 gói/giây — phát hiện packet loss nhanh hơn
```

### 3. Flood Ping — Stress test nhanh
```bash
# CẢNH BÁO: Chỉ dùng trong lab, không dùng trên production
sudo ping -f -c 10000 192.168.1.1

# Output: mỗi dấu "." = 1 gói gửi, mỗi dấu "\" = 1 gói nhận được, "." không match = lost
# Kết thúc in summary: packet loss %, min/avg/max RTT
```

### 4. Tắt DNS lookup — Hiển thị raw IP
```bash
ping -n 192.168.1.1    # Linux
ping -n google.com     # Không resolve PTR record
```

### 5. Gắn timestamp — Poor man's monitoring
```bash
ping -D google.com
# [1714012345.123456] 64 bytes from 142.250.x.x: icmp_seq=1 ttl=118 time=12ms
# Timestamp Unix epoch → import vào script, vẽ biểu đồ latency spike
```

### 6. Chỉ định source interface — Debug routing
```bash
# Buộc gói tin ra đúng interface, test policy routing / multi-homed
ping -I eth1 8.8.8.8          # Linux (dùng tên interface)
ping -I 192.168.2.1 8.8.8.8   # Linux (dùng IP nguồn)

ping -b 192.168.2.1 8.8.8.8   # macOS
```

### 7. Quiet mode — Chỉ lấy summary
```bash
ping -c 100 -q google.com
# Không in từng dòng, chỉ in summary cuối — dùng trong script
```

---

## 🔍 Cách đọc output

```
PING google.com (142.250.196.46): 56 data bytes
64 bytes from 142.250.196.46: icmp_seq=0 ttl=118 time=12.465 ms
64 bytes from 142.250.196.46: icmp_seq=1 ttl=118 time=11.832 ms
64 bytes from 142.250.196.46: icmp_seq=3 ttl=118 time=13.102 ms  ← seq nhảy từ 1 lên 3!

--- google.com ping statistics ---
4 packets transmitted, 3 packets received, 25.0% packet loss
round-trip min/avg/max/stddev = 11.832/12.466/13.102/0.518 ms
```

| Dấu hiệu | Ý nghĩa |
| :--- | :--- |
| `icmp_seq` nhảy số (1 → 3) | Gói seq=2 bị mất hoặc đến muộn |
| `packet loss > 0%` | Mạng có vấn đề — dùng `mtr` để tìm hop lỗi |
| `time` cao bất thường | Congestion, routing vòng, hoặc CPU overload ở router |
| `Request timeout` | ICMP bị block (firewall) hoặc host down |
| `ping: cannot resolve` | DNS lỗi — thử ping bằng IP trực tiếp |

---

## ⚠️ Giới hạn của ping — Khi nào cần công cụ khác?

| Tình huống | Vấn đề của ping | Công cụ thay thế |
| :--- | :--- | :--- |
| Muốn biết **lỗi ở hop nào** | ping chỉ test điểm đầu-cuối | `mtr` |
| **Firewall chặn ICMP** | ping timeout dù kết nối thực sự OK | `mtr --tcp`, `nc`, `curl` |
| Muốn test **port cụ thể** | ping không test TCP/UDP port | `nc -zv host port` |
| Muốn đo **bandwidth thực tế** | ping chỉ đo latency, không đo throughput | `iperf3` |
| Muốn **xem gói tin thực** | ping không decode payload | `tcpdump` |

---

> **Tóm lại:** `ping` là công cụ **xác nhận kết nối L3** và **phát hiện packet loss nhanh**. Biết dùng đúng cờ (đặc biệt `-s -M do` cho MTU, `-I` cho source routing) biến nó thành công cụ mạnh hơn nhiều người nghĩ.
