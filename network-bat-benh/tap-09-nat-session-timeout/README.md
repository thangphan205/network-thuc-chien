# 🩺 Ca Bệnh 09: NAT Session Timeout — Kết Nối Cứ Sau Vài Phút Không Dùng Là Đứt

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Ứng dụng kết nối Database (Connection Pool), SSH session hoặc WebSocket chạy rất ổn định khi liên tục có dữ liệu truyền qua. Nhưng chỉ cần để máy nghỉ (idle) không làm gì trong 5 phút, khi gõ lệnh tiếp theo thì màn hình đơ cứng vài chục giây rồi báo lỗi **`Connection reset by peer`** hoặc **`Broken pipe`**.
> * **Bản chất lỗi:** **NAT / Stateful Firewall Session Idle Timeout ở Tầng 4 (Transport)**. Các thiết bị NAT Gateway / Firewall trung gian (như AWS NAT Gateway, Cisco, Fortinet) có bảng lưu trạng thái phiên kết nối. Nếu trong một khoảng thời gian quy định không thấy packet nào, Firewall sẽ tự ý **xóa bỏ session khỏi bảng theo dõi** mà không báo trước cho 2 đầu.

---

## 🔬 Sơ đồ Vòng Đời NAT Session

```
[Client]                                  [NAT Gateway]                           [Database / Server]
   │                                            │                                          │
   │ 1. TCP Handshake ────────────────────────> │ (Tạo Entry: Client <-> Server) ────────> │
   │ 2. Truyền Data OK ───────────────────────> │ (Reset Timer đếm ngược về 350s) ───────> │
   │                                            │                                          │
   │    ⏳ [KHÔNG TRUYỀN GÌ TRONG 350 GIÂY - IDLE TIMEOUT]                                  │
   │                                            │                                          │
   │                                            ▼ (HẾT HẠN)                                │
   │                                    [XÓA SESSION KHỎI BẢNG!]                           │
   │                                            │                                          │
   │ 3. Sau 351s: Gửi câu lệnh SQL ───────────> │                                          │
   │                                            ▼                                          │
   │ <── Gửi lại [TCP RST] / Silent DROP ───────┤ (Không biết phiên này là của ai!)        │
   ▼                                                                                       │
[LỖI: Broken pipe / Connection Reset!]                                                     │
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-09-nat-session-timeout
docker compose up -d
```

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi (hạ timeout xuống 5s):
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy test:
   ```bash
   ./scripts/test.sh
   ```

---

### Bước 3: Chữa Bệnh (Khắc Phục Sự Cố)

```bash
./scripts/2-cure.sh
```

---

## 🧠 Bác Sĩ Mạng Đúc Kết: 3 Đơn Thuốc Trị Lỗi NAT Timeout

1. **Bật TCP Keepalive ở tầng Ứng dụng / Database Pool:**
   * Cấu hình HikariCP (Java), SQLAlchemy (Python), GORM (Golang), Knex (Node.js): Luôn bật `keepalive: true` và `keepalive_interval: 60s` (nhỏ hơn timeout của Gateway).
2. **Cấu hình SSH Client (Tránh bị đơ terminal khi không gõ):**
   * Thêm vào `~/.ssh/config`:
     ```ssh
     Host *
         ServerAliveInterval 60
         ServerAliveCountMax 3
     ```
3. **Cấu hình Linux Kernel (OS-level):**
   ```bash
   sysctl -w net.ipv4.tcp_keepalive_time=60
   sysctl -w net.ipv4.tcp_keepalive_intvl=10
   sysctl -w net.ipv4.tcp_keepalive_probes=3
   ```

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
