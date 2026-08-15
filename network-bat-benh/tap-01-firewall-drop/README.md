# 🩺 Ca Bệnh 01: Firewall Silent DROP — Ping Thông Nhưng Web Treo Timeout

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ phản hồi lệnh `ping` cực tốt (0% packet loss, RTT < 1ms), nhưng khi người dùng mở trình duyệt hoặc `curl` thì website xoay tròn vô tận rồi báo lỗi **Connection Timed Out**.
> * **Tầng nghi vấn:** Tầng 3 (Network Layer) thông suốt, nhưng Tầng 4 (Transport Layer) bị chặn bởi luật Firewall.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER NETWORK                             |
|                                                                         |
|   [Client: 172.28.1.20]                      [Web Server: 172.28.1.10]  |
|            │                                             │              |
|            │ (1) ping 172.28.1.10 (ICMP)                 │              |
|            ├────────────────────────────────────────────►│ [ICMP Stack] |
|            │◄────────────────────────────────────────────┤ (Reply ✓)    |
|            │                                             │              |
|            │ (2) curl http://172.28.1.10:80 (TCP)        │              |
|            │──[TCP SYN]─────────────────────────────────►│ [iptables]   |
|            │   (Firewall nuốt im lặng - Silent DROP)     │ (DROP 80 ✗)  |
|            │                                             │              |
|            ▼                                             ▼              |
|   [Retransmission... -> Timeout]             [Nginx Listen :80]         |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
Đứng tại thư mục `tap-01-firewall-drop/`:

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

*(Hoặc chạy thủ công từ terminal):*
```bash
# Bắt mạch L3: Ping trực tiếp IP container
docker compose exec client ping -c 3 172.28.1.10

# Bắt mạch L4/L7: Curl vào Web Server
docker compose exec client curl -Iv --connect-timeout 4 http://172.28.1.10
```

#### 🔍 Hiện tượng quan sát được:
1. **Trên Terminal:**
   * `ping 172.28.1.10`: Phản hồi 100% không mất gói nào (`0% packet loss`, RTT < 1ms).
   * `curl http://172.28.1.10`: Bị đứng im 4 giây sau đó báo lỗi `Operation timed out`.

2. **Bắt gói tin kiểm tra (tcpdump / Wireshark):**
   * Chạy lệnh tcpdump trực tiếp trên container client:
     ```bash
     docker compose exec client tcpdump -i eth0 -n "icmp or port 80"
     ```
   * **Gói ICMP:** Thấy gói `Echo (ping) request` gửi đi và nhận lại `Echo (ping) reply` ngay lập tức.
   * **Gói TCP:** Client gửi gói tin `[SYN]` nhưng Server không hề phản hồi. Xuất hiện hàng loạt gói **`[TCP Retransmission]`** (Client gửi lại gói SYN sau 1s, 2s, 4s... theo thuật toán Exponential Backoff cho đến khi hết timeout).

---

### Bước 3: Khắc Phục Sự Cố (Fix & Remediate)

Xóa bỏ luật DROP trên Firewall:
```bash
./scripts/2-fix.sh
```

Kiểm tra lại:
```bash
docker compose exec client curl -I http://172.28.1.10
```
Website lập tức phản hồi **`HTTP/1.1 200 OK`**.

*(Bạn cũng có thể truy cập từ trình duyệt máy host tại `http://localhost:8080`)*.

---

## 🧠 Phân Tích Kỹ Thuật & Đúc Kết

| Đặc điểm | Giải thích |
| :--- | :--- |
| **Tại sao Ping vẫn thông?** | `ping` sử dụng giao thức **ICMP** ở Tầng 3 (Network Layer) do Kernel Linux trực tiếp xử lý độc lập với các ứng dụng Web. |
| **Tại sao Web bị Timeout?** | Khi Firewall áp dụng hành động **`DROP` (Silent Drop)**, gói tin bị hủy âm thầm mà không gửi bất kỳ thông báo lỗi nào về. Phía Client không biết chuyện gì xảy ra nên tiếp tục gửi lại (`Retransmission`) cho đến khi cạn thời gian chờ (Timeout). |
| **Gặp trong thực tế ở đâu?** | • **AWS Security Group / Azure NSG / GCP Firewall:** Mặc định DROP mọi traffic nếu chưa khai báo Inbound Rule.<br>• **Firewall cứng (Palo Alto, Fortinet):** Cấu hình Stealth/Drop Rule.<br>• **Linux Server:** Bật `iptables` / `ufw` với policy `DROP`. |

---

## 📝 Câu Hỏi Ôn Tập

1. Vì sao `ping` vẫn phản hồi 100% nhưng trình duyệt lại xoay tròn rồi Timeout?
2. Firewall dùng luật `DROP` khác luật `REJECT` ở điểm nào về gói tin phản hồi cho client?
3. Lệnh nào cho bạn thấy ngay luật iptables nào đang chặn cổng 80?

<details><summary>Gợi ý đáp án</summary>

1. `ping` là ICMP (L3) không bị chặn; luật chỉ DROP gói TCP cổng 80 (L4). Gói SYN bị nuốt im lặng nên client cứ retransmit tới khi timeout.
2. `DROP` = im lặng nuốt gói → client treo đến timeout. `REJECT` = gửi lại TCP RST/ICMP → client báo lỗi "refused" ngay lập tức (xem Tập 02).
3. `iptables -L INPUT -n -v --line-numbers` (hoặc `iptables -S`).
</details>

---

## 🧹 Dọn dẹp Lab
Sau khi hoàn thành bài thực hành, tắt môi trường lab bằng lệnh:
```bash
docker compose down
```
