# 🩺 Ca Bệnh 01: Firewall Silent DROP — Ping Thông Nhưng Web Treo Timeout

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ phản hồi lệnh `ping` cực tốt (0% packet loss, RTT < 1ms), nhưng khi người dùng mở trình duyệt hoặc `curl` thì website xoay tròn vô tận rồi báo lỗi **Connection Timed Out**.
> * **Tầng nghi vấn:** Tầng 3 (Network Layer) thông suốt, nhưng Tầng 4 (Transport Layer) bị chặn bởi luật Firewall.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------+
|                     MÁY TÍNH CỦA BẠN                        |
|                                                             |
|   [Trình duyệt / curl]                    [ping 127.0.0.1]  |
|            │                                     │          |
|            │ (TCP:8080)                          │ (ICMP)   |
|            ▼                                     ▼          |
|   ┌─────────────────────────────────────────────────────┐   |
|   │               Wireshark bắt trên `lo0`              │   |
|   │         Filter: (tcp.port == 8080) || icmp          │   |
|   └─────────────────────────────────────────────────────┘   |
|                              │                              |
|                              ▼                              |
|   ┌─────────────────────────────────────────────────────┐   |
|   │         Docker Container: lab01-web-server          │   |
|   │                                                     │   |
|   │   [ICMP Stack]  ──> Luôn phản hồi Echo Reply (✓)    │   |
|   │                                                     │   |
|   │   [iptables Firewall] ──> DROP Port 80 (Chặn)       │   |
|   │                                                     │   |
|   │   [Nginx Web Service] ──> Listen on port 80         │   |
|   └─────────────────────────────────────────────────────┘   |
+-------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
Đứng tại thư mục `tap-01-firewall-drop/`:

```bash
docker compose up -d --build
```

Kiểm tra container đã sẵn sàng:
```bash
docker compose ps
```

---

### Bước 2: Bật Wireshark trên máy tính

1. Mở phần mềm **Wireshark**.
2. Chọn Card mạng **`Loopback: lo0`** (trên macOS/Linux) hoặc **`Adapter for loopback traffic capture`** (trên Windows).
3. Nhập **Display Filter** vào ô lọc:
   ```wireshark
   (tcp.port == 8080) || icmp
   ```

---

### Bước 3: Kích hoạt Ca Bệnh & Bắt mạch

Chạy script kích hoạt lỗi:
```bash
./scripts/1-fault.sh
```

Chạy lệnh kiểm tra từ Terminal:
```bash
./scripts/test.sh
```

#### 🔍 Hiện tượng quan sát được:
1. **Trên Terminal:**
   * `ping 127.0.0.1`: Phản hồi 100% không mất gói nào (`0% packet loss`).
   * `curl http://127.0.0.1:8080`: Bị đứng im 5 giây sau đó báo lỗi `Operation timed out`.

2. **Trên Wireshark:**
   * **Gói ICMP:** Gói `Echo (ping) request` gửi đi và nhận lại `Echo (ping) reply` ngay lập tức.
   * **Gói TCP:** Máy client gửi gói tin `[SYN]` nhưng Server không hề phản hồi. Sau đó, Wireshark xuất hiện hàng loạt gói màu đen/đỏ có nhãn **`[TCP Retransmission]`** (Client kiên nhẫn gửi lại gói SYN sau 1s, 2s, 4s... theo thuật toán Exponential Backoff).

---

### Bước 4: Chữa Bệnh (Khắc Phục Sự Cố)

Xóa bỏ luật DROP trên Firewall:
```bash
./scripts/2-cure.sh
```

Kiểm tra lại:
```bash
curl -I http://127.0.0.1:8080
```
Website lập tức phản hồi **`HTTP/1.1 200 OK`**.

Trên Wireshark, bạn sẽ thấy ngay quá trình bắt tay 3 bước hoàn hảo:
`[SYN]` → `[SYN, ACK]` → `[ACK]` → `GET / HTTP/1.1` → `HTTP/1.1 200 OK`.

---

## 🧠 Phân Tích Kỹ Thuật & Đúc Kết

| Đặc điểm | Giải thích |
| :--- | :--- |
| **Tại sao Ping vẫn thông?** | `ping` sử dụng giao thức **ICMP** ở Tầng 3 (Network Layer) do Kernel Linux trực tiếp xử lý độc lập với các ứng dụng Web. |
| **Tại sao Web bị Timeout?** | Khi Firewall áp dụng hành động **`DROP` (Silent Drop)**, gói tin bị hủy âm thầm mà không gửi bất kỳ thông báo lỗi nào về. Phía Client không biết chuyện gì xảy ra nên tiếp tục gửi lại (`Retransmission`) cho đến khi cạn thời gian chờ (Timeout). |
| **Gặp trong thực tế ở đâu?** | • **AWS Security Group / Azure NSG / GCP Firewall:** Mặc định DROP mọi traffic nếu chưa khai báo Inbound Rule.<br>• **Firewall cứng (Palo Alto, Fortinet):** Cấu hình Stealth/Drop Rule.<br>• **Linux Server:** Bật `iptables` / `ufw` với policy `DROP`. |

---

## 🧹 Dọn dẹp Lab
Sau khi hoàn thành bài thực hành, tắt môi trường lab bằng lệnh:
```bash
docker compose down
```
