# 🩺 Ca Bệnh 02: Firewall Active REJECT — Ping Thông Nhưng Web Báo Connection Refused

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ ping phản hồi 100% không mất gói nào, nhưng khi mở web hoặc `curl` thì bị báo lỗi **`Connection refused`** ngay lập tức trong 0.001 giây (không bị treo như Ca Bệnh 01).
> * **Tầng nghi vấn:** Tầng 3 (ICMP) thông suốt, Tầng 4 (TCP) bị Firewall từ chối chủ động bằng cờ `TCP RST`.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------+
|                     MÁY TÍNH CỦA BẠN                        |
|                                                             |
|   [Trình duyệt / curl]                    [ping 127.0.0.1]  |
|            │                                     │          |
|            │ (TCP:8082)                          │ (ICMP)   |
|            ▼                                     ▼          |
|   ┌─────────────────────────────────────────────────────┐   |
|   │               Wireshark bắt trên `lo0`              │   |
|   │         Filter: (tcp.port == 8082) || icmp          │   |
|   └─────────────────────────────────────────────────────┘   |
|                              │                              |
|                              ▼                              |
|   ┌─────────────────────────────────────────────────────┐   |
|   │         Docker Container: lab02-web-server          │   |
|   │                                                     │   |
|   │   [ICMP Stack]  ──> Luôn phản hồi Echo Reply (✓)    │   |
|   │                                                     │   |
|   │   [iptables REJECT] ──> Trả về TCP RST lập tức (✗)  │   |
|   └─────────────────────────────────────────────────────┘   |
+-------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
Đứng tại thư mục `tap-02-firewall-reject/`:

```bash
docker compose up -d --build
```

---

### Bước 2: Bật Wireshark trên máy tính
1. Chọn Card mạng **`Loopback: lo0`** (macOS/Linux) hoặc adapter tương ứng.
2. Nhập Display Filter:
   ```wireshark
   (tcp.port == 8082) || icmp
   ```

---

### Bước 3: Kích hoạt Ca Bệnh & Bắt mạch

Chạy script kích hoạt lỗi:
```bash
./scripts/1-fault.sh
```

Chạy kiểm tra từ Terminal:
```bash
./scripts/test.sh
```

#### 🔍 Hiện tượng quan sát được:
1. **Trên Terminal:**
   * `ping 127.0.0.1`: Phản hồi bình thường (`0% packet loss`).
   * `curl http://127.0.0.1:8082`: Báo lỗi `Failed to connect to 127.0.0.1 port 8082: Connection refused` ngay lập tức!
2. **Trên Wireshark:**
   * Client vừa gửi gói `[SYN]`.
   * Server lập tức phản hồi lại gói **`[RST, ACK]`** (màu đỏ đen). Client lập tức hủy kết nối.

---

### Bước 4: Khắc Phục Sự Cố (Fix & Remediate)

```bash
./scripts/2-fix.sh
```

Kiểm tra lại:
```bash
curl -I http://127.0.0.1:8082
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
