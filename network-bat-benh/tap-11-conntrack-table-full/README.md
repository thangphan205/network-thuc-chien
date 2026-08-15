# 🩺 Ca Bệnh 11: Tràn Bảng Conntrack — Server Mạnh Nhưng Rớt Kết Nối Ngẫu Nhiên

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Máy chủ Web/API cấu hình CPU/RAM cực khủng (RAM 64GB, CPU 16 Core), tài nguyên CPU/RAM chỉ dùng dưới 10%, băng thông mạng còn thừa thãi. Nhưng vào giờ cao điểm, hàng loạt người dùng bị lỗi ngắt kết nối ngẫu nhiên (chập chờn lúc được lúc mất).
> * **Bản chất lỗi:** **Tràn bảng theo dõi kết nối Linux Netfilter (`nf_conntrack: table full, dropping packet`)**. Linux Kernel theo dõi mọi kết nối NAT/iptables bằng module `nf_conntrack`. Khi số lượng kết nối đồng thời vượt quá ngưỡng `nf_conntrack_max`, Kernel sẽ tự động hủy (DROP) toàn bộ các gói tin TCP SYN mới!

---

## 🔬 Sơ đồ Cơ Chế Netfilter Connection Tracking

```
[Gói tin TCP SYN mới tới]
            │
            ▼
┌───────────────────────────────────────────────┐
│     Module nf_conntrack (Linux Kernel)        │
│                                               │
│   Số kết nối hiện tại: nf_conntrack_count     │
│   Giới hạn tối đa:     nf_conntrack_max       │
└───────────────────────────────────────────────┘
            │
      [Kiểm tra dung lượng]
      ┌─────┴─────┐
      ▼           ▼
  [Còn chỗ]   [BẢNG ĐÃ ĐẦY!]
      │           │
   (Cho qua)      ▼
              ┌────────────────────────────────────────────────────────┐
              │ 🚨 KERNEL LOG: nf_conntrack: table full, dropping pkg  │
              │ (Gói tin SYN bị vứt bỏ lập tức -> Client Timeout!)     │
              └────────────────────────────────────────────────────────┘
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-11-conntrack-table-full
docker compose up -d
```

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi:
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy test:
   ```bash
   ./scripts/test.sh
   ```

3. Soi log hệ thống (`dmesg`):
   ```bash
   dmesg -T | grep -i "conntrack.*full"
   ```

---

### Bước 3: Chữa Bệnh (Khắc Phục Sự Cố)

Nâng ngưỡng `nf_conntrack_max`:
```bash
./scripts/2-cure.sh
```

Kiểm tra lại bằng test tải:
```bash
./scripts/test.sh
```
Tất cả 100% request đều hoàn tất thành công (`Failed requests: 0`)!

---

## 🧠 Bác Sĩ Mạng Đúc Kết: Công Thức Tối Ưu Bảng Conntrack Cho Server High Load

1. **Công thức tính dung lượng RAM tiêu thụ:**
   * Mỗi entry conntrack tiêu tốn khoảng ~320 bytes RAM trong Kernel slab.
   * `1,000,000` entries chỉ tốn khoảng `~320MB RAM`!
2. **Cấu hình chuẩn trong `/etc/sysctl.conf`:**
   ```ini
   # Nâng giới hạn tối đa
   net.netfilter.nf_conntrack_max = 1048576

   # Giảm thời gian lưu trạng thái kết nối đóng (tránh giữ rác)
   net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
   net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
   net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
   ```
3. **Tuyệt chiêu NOTRACK (Bypass Conntrack):**
   Với các cổng Web/Reverse Proxy tải cực cao không cần NAT:
   ```bash
   iptables -t raw -A PREROUTING -p tcp --dport 80 -j NOTRACK
   iptables -t raw -A PREROUTING -p tcp --dport 443 -j NOTRACK
   ```

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
