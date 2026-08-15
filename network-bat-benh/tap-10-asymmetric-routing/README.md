# 🩺 Ca Bệnh 10: Asymmetric Routing — Ping Thông 2 Chiều Nhưng Không Vào Được Web/SSH

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Từ máy client ping sang máy chủ phản hồi rất đẹp 0% packet loss. Từ máy chủ ping ngược lại máy client cũng 0% loss. Nhưng hễ mở SSH hoặc Web thì kết nối bị đứng im và rớt ngay từ bước bắt tay.
> * **Bản chất lỗi:** **Định tuyến bất đối xứng (Asymmetric Routing)** qua Stateful Firewall. Gói `SYN` (chiều đi) đi qua Firewall A (tạo session table), nhưng gói `SYN-ACK` (chiều về) bị định tuyến đi qua Firewall B. Do Firewall B chưa từng thấy gói `SYN` trước đó nên đánh giá gói này là bất hợp lệ (`INVALID State`) và thẳng tay hủy gói tin.

---

## 🔬 Sơ đồ Định Tuyến Bất Đối Xứng

```
                    ┌─────────────────────────┐
         ┌─────────>│  Firewall A (Tạo state) ├─────────┐
         │ (Gói SYN)└─────────────────────────┘         │
         │                                              ▼
   [Client]                                         [Server]
         ▲                                              │
         │ (Gói SYN-ACK)┌────────────────────────┐      │
         └──────────────┤  Firewall B (DROP vì   │<─────┘
                        │  không có state SYN!)  │
                        └────────────────────────┘
```

---

> **⚠️ Lưu ý về phạm vi mô phỏng:** Lab này dùng **1 server** chặn gói `SYN-ACK` chiều đi bằng iptables để **tái hiện đúng TRIỆU CHỨNG** của asymmetric routing (ping thông 2 chiều, nhưng TCP đứt ở bước bắt tay). Đây **không phải** một topology 2 firewall / 2 đường về thật. Cơ chế gốc ngoài đời: gói đi qua Firewall A, gói về theo tuyến khác qua Firewall B — Firewall B không có state của kết nối nên drop `SYN-ACK`. Muốn dựng bản đầy đủ 2 router thật, dùng Containerlab (xem series `cicd-network-config`).

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-10-asymmetric-routing
docker compose up -d --build
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
1. `ping 172.28.10.10`: Thành công 100% (vì ICMP là giao thức đơn giản, ít bị phụ thuộc vào state bắt tay 3 bước).
2. `curl http://172.28.10.10`: Bị đứng im rồi timeout (vì gói `SYN-ACK` chiều về không bao giờ đến được Client).

---

### Bước 3: Khắc Phục Sự Cố (Fix & Remediate)

Đảm bảo lưu lượng 2 chiều đi qua cùng một cổng Firewall (Symmetric Path):
```bash
./scripts/2-fix.sh
```

Kiểm tra lại:
```bash
./scripts/test.sh
```
Nhận ngay kết quả `HTTP/1.1 200 OK`!

---

## 🧠 Bác Sĩ Mạng Đúc Kết: 3 Giải Pháp Cho Lỗi Asymmetric Routing

1. **Sửa bảng định tuyến (Routing Table):** Đảm bảo Default Gateway và Static Route trên cả 2 đầu đều chỉ về cùng 1 Next-Hop Firewall.
2. **Áp dụng Source NAT (SNAT) tại Firewall A:**
   * Khi gói tin đi qua Firewall A, đổi Source IP thành IP của Firewall A. Server khi trả lời sẽ bắt buộc phải gửi ngược lại về Firewall A (ép Symmetric Path).
3. **Cấu hình Firewall Clustering (Active/Active với Session Sync):**
   * Nếu bắt buộc phải chạy 2 Firewall song song, phải bật giao thức đồng bộ phiên (State Synchronization) giữa Firewall A và Firewall B.

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
