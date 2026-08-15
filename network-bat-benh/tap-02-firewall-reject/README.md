# 🩺 Ca Bệnh 02: Firewall Active REJECT — Ping Thông Nhưng Web Báo Connection Refused

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ ping phản hồi 100% không mất gói nào, nhưng khi mở web hoặc `curl` thì bị báo lỗi **`Connection refused`** ngay lập tức trong 0.001 giây (không bị treo như Ca Bệnh 01).
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

*(Hoặc chạy thủ công từ terminal):*
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
2. **Bắt gói tin kiểm tra (tcpdump):**
   * Bắt gói tin trên client:
     ```bash
     docker compose exec client tcpdump -i eth0 -n "icmp or port 80"
     ```
   * Client vừa gửi gói `[SYN]`, Server lập tức phản hồi lại gói **`[RST, ACK]`**. Client lập tức đóng socket và trả lỗi.

---

### Bước 3: Khắc Phục Sự Cố (Fix & Remediate)

```bash
./scripts/2-fix.sh
```

Kiểm tra lại:
```bash
docker compose exec client curl -I http://172.28.2.10
```
Website trả về `HTTP/1.1 200 OK` thành công!

---

## 🧠 Phân Tích Kỹ Thuật: DROP vs REJECT

| Đặc điểm | Firewall DROP (Tập 01) | Firewall REJECT / Port Closed (Tập 02) |
| :--- | :--- | :--- |
| **Phản hồi của Server** | Không nói gì (Silent Drop) | Trả về cờ `TCP RST` |
| **Trải nghiệm User** | Trình duyệt xoay tròn vô tận, sau đó `Timed Out` | Báo lỗi `Connection Refused` ngay tức thì |
| **Wireshark** | Gói `[TCP Retransmission]` lặp lại liên tục | Gói `[RST, ACK]` xuất hiện ngay sau `[SYN]` |
| **Ý nghĩa bảo mật** | Dấu hiệu máy chủ ẩn (Stealth mode) | Tiết lộ cho kẻ tấn công biết cổng này đang đóng |

---

## 📝 Câu Hỏi Ôn Tập

1. Vì sao lỗi "Connection refused" xuất hiện **ngay lập tức** chứ không treo chờ như Tập 01?
2. Khi cấu hình `REJECT --reject-with tcp-reset`, server gửi lại gói TCP gì cho client?
3. Nhìn từ phía người dùng, `DROP` và `REJECT` khác nhau ra sao khi debug?

<details><summary>Gợi ý đáp án</summary>

1. Firewall gửi ngay gói phản hồi (RST) nên client biết "bị từ chối" tức thì, không phải chờ hết timeout.
2. Gói **TCP RST** (Reset).
3. `DROP` = treo tới timeout (khó biết bị chặn hay server chết). `REJECT` = báo lỗi ngay, dễ suy ra có firewall chủ động từ chối.
</details>

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
