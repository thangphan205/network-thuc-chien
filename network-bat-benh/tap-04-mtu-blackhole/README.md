# 🩺 Ca Bệnh 04: Path MTU Blackhole — Ping Gói Nhỏ OK, Web Tải Nửa Chừng Thì Đơ

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Người dùng ping máy chủ thấy cực kỳ mượt mà. Mở website thì thấy tiêu đề trang vừa hiện lên nhưng sau đó trang web **quay vòng vòng vô tận** hoặc tải đơ nửa chừng.
> * **Bản chất lỗi:** **Path MTU Discovery (PMTUD) Blackhole**. Gói tin kích thước nhỏ (Ping 64B, TCP SYN 60B) đi qua thông suốt, nhưng khi Server gửi gói dữ liệu HTML/TLS lớn (> MTU của đường truyền), gói tin bị Router trung gian âm thầm hủy (DROP) do có cờ `DF (Don't Fragment)` mà không có thông báo ICMP Fragmentation Needed gửi về.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER NETWORK                             |
|                                                                         |
|   [Client: 172.28.4.20]                      [Web Server: 172.28.4.10]  |
|            │                                             │              |
|            │ 1. ping 64B (ICMP nhỏ) ──────────────────> │ [PASS ✓]     |
|            │ 2. TCP SYN (60B) ────────────────────────> │ [PASS ✓]     |
|            │ 3. GET / (Yêu cầu Web) ──────────────────> │ [PASS ✓]     |
|            │                                             │              |
|            │ <── 4. Trả về HTML to (> 1500B, cờ DF) ────┤              |
|            │               ▼                             │              |
|            │        [MTU BLACKHOLE]                      │              |
|            │   (Gói tin to bị vứt bỏ âm thầm)            │              |
|            │                                             │              |
|            │ <── Server gửi lại liên tục [Retransmission] ──────────────┤
|            ▼                                                            |
|   (Client đơ mãi mãi)                                                   |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-04-mtu-blackhole
docker compose up -d --build
```

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi MTU Blackhole:
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy chẩn đoán nhanh:
   ```bash
   ./scripts/test.sh
   ```

#### 🔍 Hiện tượng quan sát được:
1. **Ping nhỏ (64B):** Phản hồi cực nhanh 0% loss.
2. **Ping lớn với cờ Don't Fragment (`ping -s 1400 -M do`):** Bị mất gói 100% (Request timed out)!
3. **Truy cập Web (`curl`):** Kết nối TCP thành công (thấy dòng `Connected`), gửi `GET /` thành công, nhưng sau đó đứng im mãi mãi không nhận được Body.

---

### Bước 3: Bắt mạch trên Wireshark

1. Bắt gói tin trên card mạng Docker bridge hoặc Loopback.
2. Display filter:
   ```wireshark
   tcp.port == 80 || icmp
   ```
3. Soi gói tin:
   * Thấy quá trình bắt tay TCP `[SYN]` -> `[SYN, ACK]` -> `[ACK]` thành công.
   * Thấy gói tin Client gửi request `GET /` thành công.
   * Sau đó xuất hiện hàng loạt gói tin Server gửi lại dữ liệu lớn **`[TCP Retransmission] Len=1460`** vì Server không nhận được ACK từ Client!

---

### Bước 4: Chữa Bệnh (Khắc Phục Sự Cố)

```bash
./scripts/2-cure.sh
```

Kiểm tra lại:
```bash
docker compose exec client curl http://172.28.4.10
```
Toàn bộ trang web được tải về đầy đủ tức thì!

---

## 🧠 Bác Sĩ Mạng Đúc Kết: Giải Pháp Thực Tế Cho Lỗi MTU

1. **Nguyên nhân thực tế:** Thường xuyên xảy ra khi dữ liệu đi qua **VPN IPsec, GRE Tunnel, VXLAN, PPPoE** (các giao thức này đóng thêm Header làm giảm MTU khả dụng từ 1500 xuống 1400-1420).
2. **Đơn thuốc xử lý (Best Practices):**
   * **TCP MSS Clamping (Khuyên dùng nhất trên Router/Firewall):**
     `iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu`
     👉 Router tự động sửa giá trị MSS trong gói SYN thành kích thước nhỏ an toàn.
   * **Không bao giờ chặn ICMP Type 3 Code 4:** Mở Firewall cho phép gói ICMP thông báo "Fragmentation Needed".

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
