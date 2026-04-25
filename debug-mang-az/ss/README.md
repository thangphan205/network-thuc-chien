# 🔌 ss — X-quang hệ thống socket

`ss` (Socket Statistics) là phiên bản hiện đại thay thế `netstat`. Nhanh hơn, nhiều thông tin hơn, và không bị deprecated. Trên hầu hết distro Linux mới, `netstat` đã bị gỡ bỏ mặc định.

---

## ⚙️ ss vs netstat

| Tiêu chí | `netstat` | `ss` |
| :--- | :--- | :--- |
| **Tốc độ** | Chậm (đọc `/proc/net/*`) | Nhanh (dùng netlink socket trực tiếp) |
| **Thông tin** | Cơ bản | Chi tiết hơn: TCP internals, memory usage |
| **Filter** | Hạn chế | Mạnh mẽ với expression filter |
| **Trạng thái** | Deprecated trên nhiều distro | Chuẩn hiện tại |

---

## 📖 Cheatsheet

### 1. Xem tất cả TCP connection đang mở
```bash
ss -t       # TCP connections (ESTABLISHED)
ss -ta      # TCP connections (tất cả trạng thái)
ss -tan     # Không resolve DNS (nhanh hơn)
```

### 2. Xem port nào đang listen (cực kỳ hay dùng)
```bash
ss -tlnp
# -t: TCP, -l: listening only, -n: no DNS, -p: show process
# Output:
# State  Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
# LISTEN 0      128    0.0.0.0:22          0.0.0.0:*         users:(("sshd",pid=1234))
```

### 3. Tìm process nào đang chiếm port cụ thể
```bash
ss -tlnp sport = :8080
ss -tlnp | grep 8080
```

### 4. Xem UDP
```bash
ss -uln    # UDP listening ports
ss -uan    # Tất cả UDP
```

### 5. Filter theo state TCP
```bash
ss -t state established          # Chỉ ESTABLISHED
ss -t state time-wait            # Chỉ TIME_WAIT (nhiều = load cao)
ss -t state close-wait           # CLOSE_WAIT = app chưa đóng socket
ss -ta state fin-wait-1
```

### 6. Filter theo địa chỉ / port
```bash
ss -t dst 10.0.0.1               # Kết nối đến IP cụ thể
ss -t dport = :443               # Kết nối đến port 443
ss -t sport = :3306              # Kết nối từ port 3306 (MySQL)
ss -t src 192.168.1.0/24         # Kết nối từ subnet
```

### 7. Xem chi tiết TCP internal (advanced)
```bash
ss -tei    # -e: extended info, -i: TCP internals
# Hiển thị: cwnd (congestion window), rtt, retrans, send/recv buffer
```

### 8. Xem Unix socket (debug IPC)
```bash
ss -xl     # Unix domain sockets đang listen
ss -xp     # Unix sockets với process info
```

---

## 🔍 Đọc TCP States — Ý nghĩa thực chiến

```
Client          SYN →           Server
Client      ← SYN-ACK           Server
Client          ACK →           Server
         [ESTABLISHED — giao tiếp bình thường]

Client          FIN →           Server
Client      ← FIN-ACK           Server
Client          [TIME_WAIT]     Server
```

| State | Ý nghĩa | Dấu hiệu bất thường |
| :--- | :--- | :--- |
| `ESTABLISHED` | Kết nối đang hoạt động | Quá nhiều = đang có load |
| `TIME_WAIT` | Đợi đảm bảo FIN-ACK tới nơi (2×MSL = ~60s) | Hàng ngàn = cần `SO_REUSEADDR` hoặc tăng port range |
| `CLOSE_WAIT` | Server nhận FIN từ client nhưng app chưa gọi `close()` | **File descriptor leak** — app có bug |
| `SYN_RECV` | Đang trong quá trình 3-way handshake | Nhiều quá = SYN flood attack |
| `LISTEN` | Port đang mở, sẵn sàng nhận | Bình thường |

### Phát hiện CLOSE_WAIT leak:
```bash
ss -tan | grep CLOSE_WAIT | wc -l
# Nếu số này tăng liên tục → app có bug không đóng socket
```

### Kiểm tra TIME_WAIT:
```bash
ss -tan state time-wait | wc -l
# > 1000 → cân nhắc tune kernel:
# net.ipv4.tcp_tw_reuse = 1
# net.ipv4.ip_local_port_range = 1024 65535
```

---

## 📊 Kịch bản thực chiến

### "Port 3000 không listen, app có chạy không?"
```bash
ss -tlnp | grep 3000
# Không có output → app chưa start hoặc đang bind sai interface

# Kiểm tra app có đang chạy không:
ss -tlnp | grep -E 'node|python|java'
```

### "MySQL chạy nhưng không connect được từ ngoài"
```bash
ss -tlnp | grep 3306
# LISTEN 0 151 127.0.0.1:3306 ← bind localhost only!
# Cần đổi bind-address trong my.cnf hoặc dùng SSH tunnel
```

### "Tại sao app bị "too many open files"?"
```bash
ss -tan | wc -l                 # Tổng số socket
ss -tan state close-wait | wc -l # CLOSE_WAIT leak?
# Kiểm tra limit:
ulimit -n
cat /proc/sys/fs/file-max
```

---

> **Tóm lại:** `ss -tlnp` là lệnh đầu tiên khi debug "tại sao không kết nối được" — cho biết ngay port có listen không và process nào đang giữ. `CLOSE_WAIT` nhiều = bug app. `TIME_WAIT` nhiều = cần tune kernel.
