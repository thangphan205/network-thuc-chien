# 🩺 Ca Bệnh 06: DNS Resolution Failure — Ping IP Được Nhưng Gõ Tên Miền Thì Chết

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Người dùng gõ `ping 172.28.6.10` hoặc `curl http://172.28.6.10` thì kết nối mượt mà. Nhưng khi mở trình duyệt gõ `http://web-server` hoặc tên miền công ty thì nhận ngay thông báo lỗi **`Could not resolve host`** hoặc **`ERR_NAME_NOT_RESOLVED`**.
> * **Bản chất lỗi:** **DNS Resolution Failure ở Tầng 7 (Application Layer)**. Máy client không tìm thấy địa chỉ IP tương ứng với tên miền do cấu hình sai DNS Server (`/etc/resolv.conf`) hoặc DNS Server chết.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER NETWORK                             |
|                                                                         |
|   [Client: 172.28.6.20]                      [Web Server: 172.28.6.10]  |
|   /etc/resolv.conf trỏ:                      (Domain: web-server)       |
|   nameserver 192.0.2.53 (Chết)                                          |
|            │                                                            |
|            │ 1. DNS Query: "web-server là IP mấy?"                      |
|            ▼                                                            |
|   ┌───────────────────────────┐                                         |
|   │ DNS Server không phản hồi │                                         |
|   │ (Timeout / Unreachable)   │                                         |
|   └───────────────────────────┘                                         |
|            │                                                            |
|            ▼                                                            |
|   [Client báo: Could not resolve host!] ──x (Không bao giờ gửi được     |
|                                              HTTP request tới Server!)  |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-06-dns-resolution-failure
docker compose up -d
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
1. **Ping IP trực tiếp:** `172.28.6.10` thành công 100%.
2. **Kiểm tra `/etc/resolv.conf`:** Thấy `nameserver 192.0.2.53` (IP không có thực).
3. **Chạy `dig web-server`:** Không nhận được kết quả trả về (Connection timed out).
4. **Chạy `curl http://web-server`:** Báo lỗi ngay `curl: (6) Could not resolve host: web-server`.

---

### Bước 3: Bắt mạch trên Wireshark

1. Bắt gói tin trên card mạng Docker với filter:
   ```wireshark
   dns || icmp
   ```
2. Soi gói tin:
   * Client gửi gói tin **DNS Standard Query A web-server** tới cổng UDP 53 của IP `192.0.2.53`.
   * Hoàn toàn không có gói phản hồi DNS Response nào trở lại.

---

### Bước 4: Chữa Bệnh (Khắc Phục Sự Cố)

Khôi phục DNS server chuẩn:
```bash
./scripts/2-cure.sh
```

Kiểm tra lại:
```bash
docker compose exec client curl -I http://web-server
```
Nhận ngay kết quả **`HTTP/1.1 200 OK`**!

---

## 🧠 Bác Sĩ Mạng Đúc Kết: Quy Trình Debug DNS Chuyên Nghiệp

```
1. Test IP trước:         ping 8.8.8.8  -> Nếu thông -> L3 OK, nghi ngờ DNS.
2. Soi file DNS client:   cat /etc/resolv.conf (Linux/Mac) hoặc ipconfig /all (Windows).
3. Test DNS Query cụ thể: dig +short example.com @8.8.8.8
4. Trace luồng phân giải: dig +trace example.com
5. Check file hosts local: cat /etc/hosts (tránh trường hợp bị ai đó gán cứng IP sai).
```

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
