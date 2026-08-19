# 🩺 Ca Bệnh 02: Firewall Active REJECT — Ping Thông Nhưng Web Báo Connection Refused

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ phản hồi `ping` 100% không mất gói nào (RTT < 1ms), nhưng khi người dùng mở web hoặc `curl` thì bị báo lỗi **`Connection refused`** ngay lập tức trong 0.001 giây (không bị treo xoay tròn như Ca Bệnh 01).
> * **Tầng nghi vấn:** Tầng 3 (ICMP) thông suốt, Tầng 4 (TCP) bị Firewall từ chối chủ động bằng cờ `TCP RST`.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER NETWORK                             |
|                                                                         |
|   [Client: 172.28.2.20]                      [Web Server: 172.28.2.10]  |
|            │                                             │              |
|            │ (1) ping 172.28.2.10 (ICMP)                 │              |
|            ├────────────────────────────────────────────►│ [ICMP Stack] |
|            │◄────────────────────────────────────────────┤ (Reply ✓)    |
|            │                                             │              |
|            │ (2) curl http://172.28.2.10:80 (TCP)        │              |
|            │──[TCP SYN]─────────────────────────────────►│ [iptables]   |
|            │◄──[TCP RST, ACK] (Từ chối chủ động)────────┤ (REJECT ✗)   |
|            │                                             │              |
|            ▼                                             ▼              |
|   [Connection Refused!]                      [Nginx Listen :80]         |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
Đứng tại thư mục `tap-02-firewall-reject/`:

```bash
docker compose up -d --build
```

Kiểm tra các container đã sẵn sàng:
```bash
docker compose ps
```

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

Chạy script kích hoạt lỗi:
```bash
./scripts/1-fault.sh
```

Chạy lệnh kiểm tra tự động:
```bash
./scripts/test.sh
```

*(Hoặc chạy thủ công từng bước từ terminal):*
```bash
# Bắt mạch L3: Ping trực tiếp IP container
docker compose exec client ping -c 3 172.28.2.10

# Bắt mạch L4: Curl vào Web Server
docker compose exec client curl -Iv http://172.28.2.10
```

#### 🔍 Hiện tượng quan sát được:
1. **Trên Terminal:**
   * `ping 172.28.2.10`: Phản hồi bình thường (`0% packet loss`, RTT < 1ms).
   * `curl http://172.28.2.10`: Báo lỗi `Connection refused` ngay lập tức trong 0.001 giây!

2. **Bắt gói tin kiểm tra (tcpdump / Wireshark):**
   * Chạy lệnh tcpdump trực tiếp trên container client:
     ```bash
     docker compose exec client tcpdump -i eth0 -n "icmp or port 80"
     ```
   * **Gói ICMP:** Thấy gói `Echo (ping) request` gửi đi và nhận lại `Echo (ping) reply` ngay lập tức (L3 hoạt động tốt).
   * **Gói TCP:** Client vừa gửi gói `[SYN]` thì Server lập tức phản hồi lại gói **`[RST, ACK]`**. Client lập tức đóng socket và trả lỗi `Connection refused` thay vì kiên nhẫn retransmit như trường hợp `DROP`.

> 🦈 **Mẹo soi bằng Wireshark:**
> ```bash
> # Bắt gói xuất ra file pcap trong container
> docker compose exec client tcpdump -i eth0 -n "tcp port 80" -w /tmp/cap02.pcap
> 
> # Copy file ra máy host và mở bằng Wireshark
> docker compose cp client:/tmp/cap02.pcap ./cap02.pcap
> wireshark ./cap02.pcap
> ```
> *Display Filter gợi ý:* `tcp.port == 80 || icmp` hoặc `tcp.flags.reset == 1`.

---

### Bước 3: Khắc Phục Sự Cố (Fix & Remediate)

Xóa bỏ luật REJECT trên Firewall:
```bash
./scripts/2-fix.sh
```

Kiểm tra lại:
```bash
docker compose exec client curl -I http://172.28.2.10
```
Website lập tức phản hồi **`HTTP/1.1 200 OK`** thành công!

*(Bạn cũng có thể truy cập từ trình duyệt máy host tại `http://localhost:8082`)*.

---

## 🧠 Phân Tích Kỹ Thuật: DROP vs REJECT

### 1. Bảng so sánh bản chất kỹ thuật

| Đặc điểm | Firewall DROP (Tập 01) | Firewall REJECT (Tập 02) |
| :--- | :--- | :--- |
| **Phản hồi của Server** | Không nói gì (Silent Drop) | Trả về cờ `TCP RST` (hoặc ICMP Port Unreachable) |
| **Trải nghiệm User** | Trình duyệt xoay tròn vô tận, sau đó `Timed Out` | Báo lỗi `Connection Refused` ngay tức thì |
| **Wireshark** | Gói `[TCP Retransmission]` lặp lại liên tục | Gói `[RST, ACK]` xuất hiện ngay sau `[SYN]` |
| **Ý nghĩa bảo mật** | Dấu hiệu máy chủ ẩn (Stealth mode) — Cloud mặc định dùng | Tiết lộ cho kẻ tấn công biết IP máy chủ đang online |

### 2. Gặp trong thực tế ở đâu?
* **Linux Server với iptables / nftables:** Cấu hình luật `-j REJECT --reject-with tcp-reset` hoặc `-j REJECT --reject-with icmp-port-unreachable`.
* **Firewall nội bộ doanh nghiệp (Internal LAN/VPC):** Thường thích dùng `REJECT` hơn `DROP` để các ứng dụng nội bộ biết lỗi ngay mà fail-fast / retry logic thay vì treo chờ timeout gây nghẽn hàng đợi (connection pool).

### 3. ⚠️ Bẫy chẩn đoán thực tế: Phân biệt "Port Closed" vs "Firewall REJECT"
> **Câu hỏi:** Cả 2 trường hợp sau đều trả về `TCP RST` và gây lỗi `Connection refused`:
> 1. Web server bị tắt / Nginx chết (Port closed - Kernel tự trả RST).
> 2. Web server vẫn đang chạy, nhưng Firewall chặn bằng `REJECT --reject-with tcp-reset`.
>
> **Cách phân biệt chính xác:**
> * Bước 1: Đứng tại server chạy `ss -tulpn | grep :80` → Nếu thấy Nginx đang `LISTEN`, chứng tỏ Web Server vẫn sống.
> * Bước 2: Kiểm tra bảng iptables bằng `iptables -L INPUT -n -v` → Sẽ thấy rule `REJECT` kèm số lượng packet/bytes bị chặn đếm tăng lên!

---

## 📝 Câu Hỏi Ôn Tập

1. Vì sao lỗi "Connection refused" xuất hiện **ngay lập tức** chứ không treo chờ như Tập 01?
2. Khi cấu hình `REJECT --reject-with tcp-reset`, server gửi lại gói TCP gì cho client?
3. Nhìn từ phía người dùng, `DROP` và `REJECT` khác nhau ra sao khi debug?
4. Nếu không có Firewall nào được cài đặt nhưng Nginx bị crash/dừng dịch vụ, client kết nối vào cổng 80 sẽ nhận được phản hồi gì từ Kernel?

<details><summary>Gợi ý đáp án</summary>

1. Vì Firewall chủ động phản hồi ngay gói `TCP RST`, client nhận được tín hiệu đóng kết nối tức thì nên không cần phải gửi lại (retransmit) chờ timeout.
2. Gói **`[RST, ACK]`** (Reset & Acknowledge).
3. `DROP` = kết nối bị treo tới khi timeout (khó phân biệt mạng đứt hay server chết). `REJECT` = báo lỗi ngay lập tức (fail-fast).
4. Kernel của máy chủ sẽ tự động gửi trả gói **`TCP RST`** (với hành vi giống hệt như Firewall REJECT), do cổng đó không có tiến trình nào đang lắng nghe (`LISTEN`).
</details>

---

## 🧹 Dọn dẹp Lab
Sau khi hoàn thành bài thực hành, tắt môi trường lab bằng lệnh:
```bash
docker compose down
```

