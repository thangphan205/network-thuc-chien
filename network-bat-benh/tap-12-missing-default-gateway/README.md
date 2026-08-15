# 🩺 Ca Bệnh 12: Missing Default Gateway — Trong LAN Thông Suốt, Ra Ngoài Bị Chặn

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy tính trong công ty cắm dây mạng vẫn ping và chia sẻ file với các máy đồng nghiệp trong cùng phòng ban (cùng mạng LAN) rất tốt. Nhưng cứ mở web ra ngoài Internet hoặc ping `8.8.8.8` thì nhận ngay thông báo lỗi: **`connect: Network is unreachable`** hoặc **`Destination Host Unreachable`**.
> * **Bản chất lỗi:** **Thiếu Default Gateway ở Tầng 3 (Network/Routing)**. Bảng định tuyến (`Routing Table`) của hệ điều hành không có dòng `0.0.0.0/0` (Default Route) nên không biết phải chuyển tiếp gói tin ra Router nào khi đích đến nằm ngoài dải mạng LAN hiện tại.

---

## 🔬 Sơ đồ Quyết Định Định Tuyến (Routing Decision)

```
[Ứng dụng gửi gói tin tới IP Đích: 8.8.8.8]
                    │
                    ▼
       ┌────────────────────────┐
       │ Kiểm tra Bảng Route    │
       │ (ip route show)        │
       └────────────────────────┘
                    │
      [IP Đích có thuộc dải LAN không?]
      ┌─────────────┴─────────────┐
   (CÓ: 172.28.12.10)        (KHÔNG: 8.8.8.8)
      │                           │
      ▼                           ▼
[Gửi thẳng qua ARP/Switch]    [Tìm dòng "default via <Gateway>"]
      (✓ PASS)                    │
                            ┌─────┴─────┐
                            ▼           ▼
                       [CÓ Gateway]  [KHÔNG CÓ GATEWAY!]
                            │           │
                        (Gửi Router)    ▼
                                    ┌─────────────────────────────┐
                                    │ 🚨 LỖI: Network Unreachable! │
                                    │ (Kernel hủy gói ngay tại    │
                                    │  máy client!)               │
                                    └─────────────────────────────┘
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-12-missing-default-gateway
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
1. **Kiểm tra `ip route show`:**
   ```
   172.28.12.0/24 dev eth0 scope link  src 172.28.12.20
   ```
   👉 Hoàn toàn **biến mất dòng `default via 172.28.12.1`**!
2. **Ping nội bộ (`172.28.12.10`):** Phản hồi bình thường 0% loss.
3. **Ping Internet (`1.1.1.1`):** Báo lỗi ngay lập tức `ping: connect: Network is unreachable`.

---

### Bước 3: Chữa Bệnh (Khắc Phục Sự Cố)

Thêm lại Default Route:
```bash
./scripts/2-cure.sh
```

Kiểm tra lại:
```bash
./scripts/test.sh
```
Dòng `default via 172.28.12.1 dev eth0` xuất hiện trở lại và Ping ra Internet thành công!

---

## 🧠 Bác Sĩ Mạng Đúc Kết

1. **Nguyên tắc "Cửa ngõ mặc định":** Mọi thiết bị IP khi muốn nói chuyện với một địa chỉ không nằm trong Subnet của nó đều bắt buộc phải gửi gói tin đến **Default Gateway**.
2. **Nguyên nhân thực tế:**
   * Cấu hình IP tĩnh (Static IP) bằng tay nhưng quên điền ô *Default Gateway*.
   * Máy chủ DHCP bị lỗi cấu hình (thiếu `DHCP Option 3 - Router`).
   * Cấu hình sai Subnet Mask (ví dụ: máy tính tưởng cả thế giới nằm trong dải `/8` của nó nên cố gắng broadcast ARP thay vì gửi qua Gateway).

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
