# 🩺 Ca Bệnh 07: TLS Clock Skew — Lỗi Chứng Chỉ Không Hợp Lệ Do Sai Giờ Hệ Thống

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ ping được, port 443 kết nối TCP được, nhưng khi mở trình duyệt truy cập HTTPS thì bị chặn lại bởi màn hình cảnh báo đỏ rực: **`Your connection is not private`**, **`NET::ERR_CERT_DATE_INVALID`** hoặc `curl: (60) SSL certificate problem: certificate has expired`.
> * **Bản chất lỗi:** **Lỗi Bắt tay TLS ở Tầng 5/6 (Session/Presentation)** do ngày giờ hệ thống trên máy tính Client hoặc Server bị sai lệch (Clock Skew / mất đồng bộ NTP) khiến chứng chỉ số bị coi là chưa đến hạn hoặc đã hết hạn.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                     MÁY TÍNH CỦA BẠN (Hoặc Client)                      |
|                                                                         |
|   1. TCP 3-Way Handshake (Port 443) ──────────────> [PASS ✓]            |
|   2. Client Hello (TLS) ──────────────────────────> [PASS ✓]            |
|   3. <── Server Hello + Certificate (X.509) ───────┤                    |
|            │                                                            |
|            ▼                                                            |
|   ┌─────────────────────────────────────────────────────┐               |
|   │ Client kiểm tra thời hạn: NotBefore <= Now <= NotAfter │            |
|   │ Phát hiện: Đồng hồ máy bị lệch giờ!                 │               |
|   └─────────────────────────────────────────────────────┘               |
|            │                                                            |
|            ▼                                                            |
|   [FATAL ALERT: Certificate Expired / Bad Certificate]                  |
|   (Bắt tay TLS bị đứt ngay lập tức!)                                    |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-07-tls-clock-skew
docker compose up -d
```

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi:
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy kiểm tra:
   ```bash
   ./scripts/test.sh
   ```

#### 🔍 Hiện tượng quan sát được:
1. **TCP Handshake:** Cổng `8443` mở và kết nối thành công.
2. **OpenSSL s_client:** Trả về mã lỗi:
   ```
   Verify return code: 10 (certificate has expired)
   ```
3. **Wireshark:** Thấy gói `Client Hello` -> `Server Hello` -> Sau đó Client lập tức gửi gói tin **`TLSv1.2 / TLSv1.3 Alert (Level: Fatal, Description: Bad Certificate)`** và đóng kết nối.

---

### Bước 3: Chữa Bệnh (Khắc Phục Sự Cố)

Áp dụng chứng chỉ hợp lệ và đồng bộ thời gian:
```bash
./scripts/2-cure.sh
```

Kiểm tra lại:
```bash
./scripts/test.sh
```
Kết quả: `Verify return code: 0 (ok)` và nhận phản hồi `CA BENH 07: KET NOI HTTPS THANH CONG (TLS OK)!`

---

## 🧠 Bác Sĩ Mạng Đúc Kết

1. **Bản chất X.509 Certificate:** Mọi chứng chỉ SSL/TLS đều có 2 trường mốc thời gian bắt buộc:
   * `Not Before`: Thời điểm chứng chỉ bắt đầu có hiệu lực.
   * `Not After`: Thời điểm chứng chỉ hết hạn.
2. **Nguyên nhân thực tế:**
   * Pin CMOS trên máy chủ/máy trạm bị hết -> Khởi động lại bị nhảy về năm 2000.
   * Service đồng bộ thời gian NTP (`systemd-timesyncd`, `chrony`, `ntp`) bị dừng hoặc bị firewall chặn cổng UDP 123.
   * Máy ảo (VM) sau khi Restore Snapshot bị lệch thời gian so với thực tế.

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
