# 🩺 Ca Bệnh 03: Bind Localhost — Đứng Tại Server Vào Được, Máy Khác Thì Không

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Kỹ sư SSH vào máy chủ và gõ `curl http://localhost` thì thấy website chạy `200 OK` ngon lành. Nhưng người dùng hoặc các máy khác trong cùng mạng gõ vào IP máy chủ (`http://172.28.3.10` hoặc IP LAN) thì bị báo lỗi **Connection refused**.
> * **Bản chất lỗi:** Ứng dụng/Web Server chỉ lắng nghe (bind) trên địa chỉ Loopback `127.0.0.1` thay vì lắng nghe trên tất cả các card mạng `0.0.0.0`.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER NETWORK                             |
|                                                                         |
|   [Client: 172.28.3.20]                      [Web Server: 172.28.3.10]  |
|            │                                             │              |
|            │ curl http://172.28.3.10:80                  │              |
|            │ (Gửi vào IP Card eth0)                      │              |
|            ▼                                             ▼              |
|   ┌──────────────────┐               ┌──────────────────────────────┐   |
|   │ Connection       │  <──(RST)──   │ Card eth0 (172.28.3.10):     │   |
|   │ Refused!         │               │ KHÔNG CÓ AI LẮNG NGHE!       │   |
|   └──────────────────┘               ├──────────────────────────────┤   |
|                                      │ Card lo (127.0.0.1):         │   |
|                                      │ Nginx chỉ lắng nghe ở đây!   │   |
|                                      │ (curl 127.0.0.1 -> 200 OK)   │   |
|                                      └──────────────────────────────┘   |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-03-bind-localhost
docker compose up -d --build
```

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi:
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy chẩn đoán nhanh:
   ```bash
   ./scripts/test.sh
   ```

#### 🔍 Hiện tượng quan sát được:
* **Tại máy chủ:** `curl http://127.0.0.1` trả về `200 OK`.
* **Soi bảng Socket (`ss -tulpn` hoặc `netstat -tulpn`):**
  ```
  tcp   LISTEN   0   511   127.0.0.1:80   0.0.0.0:*   users:(("nginx",...))
  ```
  👉 Thấy rõ cột *Local Address* ghi đích danh `127.0.0.1:80`.
* **Từ máy Client:** Gọi sang `172.28.3.10` bị `Connection refused` ngay lập tức!

---

### Bước 3: Khắc Phục Sự Cố (Fix & Remediate)

Đổi cấu hình Nginx sang lắng nghe `0.0.0.0` (tất cả interfaces):
```bash
./scripts/2-fix.sh
```

Kiểm tra lại từ Client:
```bash
docker compose exec client curl -I http://172.28.3.10
```
Kết quả trả về **`HTTP/1.1 200 OK`**!

---

## 🧠 Phân Tích Kỹ Thuật: `127.0.0.1` vs `0.0.0.0`

| Cấu hình Bind | Ý nghĩa kỹ thuật | Khả năng truy cập từ ngoài |
| :--- | :--- | :--- |
| **`listen 127.0.0.1:80`** | Chỉ lắng nghe trên Loopback interface (`lo`). | ❌ **Chỉ nội bộ máy đó gọi được**, bên ngoài bị từ chối (Connection Refused). |
| **`listen 0.0.0.0:80`** (hoặc `listen 80`) | Lắng nghe trên **TẤT CẢ** các card mạng hiện có (Loopback, LAN, Public IP, Docker IP...). | ✅ **Mọi máy tính cùng mạng đều truy cập được**. |

> 💡 **Thực tế hay gặp:** Các framework backend (Flask, Django, Node.js Express, Spring Boot, FastAPI) khi chạy ở chế độ dev thường mặc định bind `127.0.0.1:8000` / `localhost:3000`. Khi deploy lên Docker/Kubernetes nếu không đổi thành `0.0.0.0` thì bên ngoài hoàn toàn không gọi vào container được!

---

## 📝 Câu Hỏi Ôn Tập

1. Vì sao đứng **tại server** curl `127.0.0.1` được, nhưng máy khác gọi vào IP server thì "Connection refused"?
2. Lệnh nào cho thấy tiến trình đang lắng nghe trên địa chỉ nào (`127.0.0.1` hay `0.0.0.0`)?
3. Sửa lỗi này bằng cách đổi `listen` thành gì?

<details><summary>Gợi ý đáp án</summary>

1. Nginx bind vào `127.0.0.1` (loopback) nên chỉ nhận kết nối từ chính máy đó; gói từ ngoài vào không có socket nào lắng nghe → RST/refused.
2. `ss -tulpn` (hoặc `netstat -tulpn`). Cột `Local Address` là `127.0.0.1:80` khi lỗi, `0.0.0.0:80` khi đúng.
3. `listen 80;` (tương đương `0.0.0.0:80`) để nghe trên mọi card mạng.
</details>

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
