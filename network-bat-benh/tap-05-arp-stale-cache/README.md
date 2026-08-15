# 🩺 Ca Bệnh 05: Stale ARP Cache — Đổi IP/Card Mạng Xong Cả Mạng Mất Kết Nối

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ vừa được nâng cấp card mạng, thay thế phần cứng hoặc chuyển đổi IP dự phòng (VIP / Keepalived / Failover). Ngay sau đó, các máy client trong cùng mạng LAN không thể nào ping hay kết nối được tới IP máy chủ nữa, dù cấu hình IP và subnet mask đều chuẩn 100%.
> * **Bản chất lỗi:** **Stale ARP Cache ở Tầng 2 (Data Link Layer)**. Bảng ARP của các máy Client vẫn đang lưu địa chỉ MAC cũ của máy chủ đã chết, nên toàn bộ khung tin (Ethernet Frame) gửi đi đều hướng về MAC không tồn tại.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER LAN (172.28.5.0/24)                 |
|                                                                         |
|   [Client: 172.28.5.20]                      [Server: 172.28.5.10]      |
|   Bảng ARP lưu:                              MAC thực tế hiện tại:      |
|   172.28.5.10 -> MAC CŨ (..:ee)              02:42:ac:1c:05:0a          |
|            │                                             │              |
|            │ Frame có Dst MAC: ..:ee                     │              |
|            │ (Gửi vào hư vô)                             │              |
|            ▼                                             │              |
|   ┌──────────────────┐                                   │              |
|   │ Switch drop      │                                   │              |
|   │ (Packet Loss)    │                                   │              |
|   └──────────────────┘                                   │              |
|                                                          │              |
|   [CURE: Gratuitous ARP / Flush ARP] ────────────────────┘              |
|   -> Cập nhật đúng MAC thực tế -> Thông mạng!                           |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-05-arp-stale-cache
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
1. **Soi MAC thực tế của Server:** `02:42:ac:1c:05:0a` (hoặc tương tự).
2. **Soi bảng ARP trên Client (`ip neigh show`):**
   ```
   172.28.5.10 dev eth0 lladdr 02:42:ac:1c:05:ee PERMANENT
   ```
   👉 Client đang map IP `172.28.5.10` sang MAC giả `02:42:ac:1c:05:ee`!
3. **Ping:** Bị mất gói 100% (`Destination Host Unreachable` hoặc Timeout).

---

### Bước 3: Bắt mạch trên Wireshark

1. Bắt gói tin trên card Docker bridge với Display Filter:
   ```wireshark
   arp || icmp
   ```
2. Soi gói tin:
   * Client gửi gói tin ICMP Request bọc trong Ethernet Frame có **Destination MAC** là MAC cũ.
   * Server không bao giờ nhận được vì card mạng của Server chỉ bắt frame có MAC của chính nó hoặc Broadcast.

---

### Bước 4: Chữa Bệnh (Khắc Phục Sự Cố)

Làm mới bảng ARP trên Client:
```bash
./scripts/2-cure.sh
```

Kiểm tra lại:
```bash
docker compose exec client ping -c 3 172.28.5.10
```
Ping thông suốt 0% packet loss!

---

## 🧠 Bác Sĩ Mạng Đúc Kết: Cách Xử Lý ARP Trong Môi Trường Sản Xuất

1. **Gratuitous ARP (GARP):** Khi máy chủ đổi IP, failover VIP (Keepalived / CARP) hoặc thay card mạng, server PHẢI chủ động gửi một gói tin **Gratuitous ARP Request/Reply** broadcast ra toàn mạng (`arping -U -c 3 -I eth0 <IP_VIP>`) để yêu cầu toàn bộ Switch và Client trong LAN cập nhật bảng ARP ngay lập tức.
2. **Lệnh xóa cache ARP nhanh trên Linux:**
   ```bash
   ip neigh flush dev eth0
   # hoặc xóa 1 IP cụ thể:
   ip neigh del 192.168.1.100 dev eth0
   ```

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
