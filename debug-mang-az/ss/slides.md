---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', 'Noto Sans', sans-serif;
    font-size: 22px;
    background: #0f1117;
    color: #e2e8f0;
  }
  h1 { color: #63b3ed; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #68d391; font-size: 1.4em; border-bottom: 2px solid #68d391; padding-bottom: 0.2em; }
  h3 { color: #f6ad55; font-size: 1.1em; }
  code { background: #1e2130; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1e2130; border-left: 4px solid #63b3ed; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  .hljs-keyword, .hljs-selector-tag { color: #ff79c6; }
  .hljs-string, .hljs-addition { color: #f1fa8c; }
  .hljs-attr, .hljs-attribute { color: #79b8ff; }
  .hljs-number, .hljs-literal { color: #bd93f9; }
  .hljs-comment { color: #6272a4; font-style: italic; }
  .hljs-variable, .hljs-template-variable { color: #ffb86c; }
  .hljs-built_in, .hljs-name, .hljs-type { color: #50fa7b; }
  .hljs-meta { color: #ff5555; }
  .hljs-title, .hljs-section { color: #8be9fd; }
  .hljs-bullet, .hljs-symbol { color: #ffb86c; }
  .hljs-params, .hljs-subst { color: #e2e8f0; }
  .hljs-deletion { color: #ff5555; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  th { background: #1e4976; color: #e2f0ff; padding: 10px 14px; font-weight: 600; letter-spacing: 0.03em; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a3550; color: #e2e8f0; background: #1a2035; }
  tr:nth-child(even) td { background: #232d47; }
  tr:hover td { background: #2a3a5c; }
  blockquote { border-left: 4px solid #f6ad55; padding-left: 16px; color: #b0bcd0; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  section.title {
    background: linear-gradient(135deg, #0f1117 0%, #1a2040 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
    padding: 60px 80px;
  }
  section.title h1 { font-size: 2.8em; color: #63b3ed; border: none; }
  section.title h2 { font-size: 1.3em; color: #68d391; border: none; margin-top: 0.2em; }
  section.title p { color: #a0aec0; font-size: 0.9em; margin-top: 16px; }
  section.divider {
    background: linear-gradient(135deg, #1a2040 0%, #0f1117 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    text-align: center;
  }
  section.divider h1 { font-size: 2.5em; border: none; }
  section.divider h2 { border: none; }
  .good { color: #68d391; font-weight: bold; }
  .bad  { color: #fc8181; font-weight: bold; }
  .warn { color: #f6ad55; font-weight: bold; }
---

<!-- _class: title -->

# 🔌 ss
## Socket Statistics — X-quang hệ thống socket

**Network Thực Chiến** · Series: Debug Mạng từ A–Z · Tập 03

---

## 📋 Nội dung

1. **ss là gì?** — Tại sao thay thế `netstat`
2. **ss vs netstat** — So sánh chi tiết
3. **Flags & Cú pháp** — Bộ tham số cốt lõi
4. **Cheatsheet** — 8 nhóm lệnh thực chiến
5. **Đọc TCP States** — Ý nghĩa từng trạng thái
6. **CLOSE_WAIT & TIME_WAIT** — Phát hiện bug & tune kernel
7. **Kịch bản thực chiến** — 3 tình huống hay gặp nhất

---

<!-- _class: divider -->

# 🎯 Phần 1
## ss là gì?

---

## Vấn đề với netstat

`netstat` là công cụ kinh điển để xem socket — nhưng đã **deprecated** trên hầu hết distro Linux mới:

```bash
# Ubuntu/Debian mới: netstat không còn cài mặc định
netstat -tlnp
# → bash: netstat: command not found

# Lý do netstat chậm:
# Đọc từng file trong /proc/net/* → parse text → hiển thị
# Với hàng nghìn connection: rất chậm
```

**`ss` giải quyết các vấn đề này:**

- Giao tiếp trực tiếp qua **netlink socket** với kernel → nhanh hơn nhiều
- Hiển thị **TCP internals**: congestion window, RTT, retransmit counter
- Filter expression mạnh mẽ: theo state, IP, port, subnet

> `ss` = **Socket Statistics** — thay thế chính thức của `netstat`.

---

## ss vs netstat — So sánh chi tiết

| Tiêu chí | `netstat` | `ss` |
| :--- | :--- | :--- |
| **Nguồn dữ liệu** | Đọc `/proc/net/*` (text parsing) | Netlink socket trực tiếp |
| **Tốc độ** | Chậm — nghẽn khi nhiều connection | Nhanh — không qua text layer |
| **TCP internals** | Không có | ✅ cwnd, rtt, retrans, buffer |
| **Filter** | Hạn chế (grep) | Mạnh: expression theo state/IP/port |
| **Trạng thái** | Deprecated trên nhiều distro | Chuẩn hiện tại |
| **Cú pháp** | `netstat -tlnp` | `ss -tlnp` (tương tự — dễ chuyển đổi) |

> 💡 Cú pháp hầu như giống nhau. Chuyển từ `netstat` sang `ss`: chỉ cần đổi tên lệnh.

---

<!-- _class: divider -->

# 🚀 Phần 2
## Flags & Cheatsheet

---

## Flags cốt lõi

| Flag | Ý nghĩa | Ví dụ |
| :--- | :--- | :--- |
| `-t` | TCP connections | `ss -t` |
| `-u` | UDP connections | `ss -u` |
| `-l` | Listening sockets only | `ss -l` |
| `-a` | All (listening + connected) | `ss -ta` |
| `-n` | No DNS resolve (số thay tên) | `ss -tn` |
| `-p` | Show process (PID + tên) | `ss -tp` |
| `-e` | Extended info | `ss -te` |
| `-i` | TCP internals | `ss -ti` |
| `-x` | Unix domain sockets | `ss -x` |

**Lệnh vàng — nhớ 1 lệnh này là đủ:**
```bash
ss -tlnp   # TCP + Listening + No DNS + Process
```

---

## Cheatsheet — Nhóm 1: TCP connections

```bash
ss -t       # ESTABLISHED TCP connections
ss -ta      # Tất cả trạng thái TCP
ss -tan     # Không resolve DNS (nhanh hơn, dễ đọc hơn)
```

Output mẫu:
```
State    Recv-Q  Send-Q  Local Address:Port   Peer Address:Port
ESTAB    0       0       192.168.1.10:52341   142.250.196.46:443
ESTAB    0       0       192.168.1.10:45123   10.0.0.5:5432
```

| Cột | Ý nghĩa |
| :--- | :--- |
| **State** | Trạng thái TCP hiện tại |
| **Recv-Q** | Bytes đã nhận nhưng app chưa đọc |
| **Send-Q** | Bytes đã gửi nhưng chưa được ACK |
| **Local / Peer** | Địa chỉ:port hai đầu kết nối |

---

## Cheatsheet — Nhóm 2: Port đang listen

```bash
ss -tlnp
```

```
State   Recv-Q  Send-Q  Local Address:Port  Peer Address:Port  Process
LISTEN  0       128     0.0.0.0:22          0.0.0.0:*          users:(("sshd",pid=1234,fd=3))
LISTEN  0       511     0.0.0.0:80          0.0.0.0:*          users:(("nginx",pid=5678,fd=6))
LISTEN  0       128     127.0.0.1:3306      0.0.0.0:*          users:(("mysqld",pid=910,fd=21))
```

**Đọc output:**
- `0.0.0.0:22` → SSH bind tất cả interface ✅
- `127.0.0.1:3306` → MySQL chỉ bind localhost ⚠️ (không reach từ ngoài)
- `Recv-Q = 0` → Không có kết nối đang chờ xử lý (bình thường)

---

## Cheatsheet — Nhóm 3: Tìm process theo port

```bash
ss -tlnp sport = :8080      # Process đang listen port 8080
ss -tlnp | grep 8080        # Tương tự, dùng grep

ss -tnp dport = :5432       # Ai đang kết nối đến PostgreSQL
ss -tnp | grep :3306        # Ai đang kết nối đến MySQL
```

**Tìm process đang chiếm port — rất hay dùng khi deploy:**
```bash
ss -tlnp sport = :80
# Nếu trống → nginx/apache chưa chạy
# Nếu có output → xem cột Process để biết PID
```

---

## Cheatsheet — Nhóm 4: Filter theo state TCP

```bash
ss -t state established          # Chỉ ESTABLISHED
ss -t state time-wait            # TIME_WAIT (nhiều = high load)
ss -t state close-wait           # CLOSE_WAIT = app bug
ss -t state syn-recv             # SYN_RECV (nhiều = SYN flood?)
ss -t state listening            # Tương đương -l

# Đếm nhanh:
ss -tan state time-wait | wc -l
ss -tan state close-wait | wc -l
```

---

## Cheatsheet — Nhóm 5: Filter theo địa chỉ / port

```bash
ss -t dst 10.0.0.1               # Kết nối đến IP cụ thể
ss -t dport = :443               # Kết nối đến HTTPS
ss -t sport = :3306              # Kết nối từ port MySQL
ss -t src 192.168.1.0/24         # Kết nối từ subnet
ss -t dst 10.0.0.0/8             # Kết nối đến toàn bộ subnet

# Kết hợp nhiều điều kiện:
ss -t dst 10.0.0.1 dport = :5432
```

---

## Cheatsheet — Nhóm 6 & 7 & 8

### TCP internals (advanced)
```bash
ss -tei    # -e: extended, -i: TCP internals
# Hiển thị: cwnd (congestion window), rtt, retrans, send/recv buffer
```

Output mẫu:
```
ESTAB  0  0  192.168.1.10:52341  142.250.x.x:443
  cubic wscale:7,7 rto:220 rtt:20.5/2.1 cwnd:10 bytes_sent:4096 retrans:0/1
```

### UDP
```bash
ss -uln    # UDP listening ports
ss -uan    # Tất cả UDP
```

### Unix domain sockets (IPC)
```bash
ss -xl     # Unix sockets đang listen
ss -xp     # Unix sockets với process info
```

---

<!-- _class: divider -->

# 🔍 Phần 3
## Đọc TCP States

---

## TCP Lifecycle — Sơ đồ

```
          CLIENT                        SERVER
             │                             │
             │──────── SYN ───────────────►│  SYN_SENT / SYN_RECV
             │◄─────── SYN-ACK ────────────│
             │──────── ACK ───────────────►│
             │                             │
             │     [ESTABLISHED]           │  ← Giao tiếp bình thường
             │                             │
             │──────── FIN ───────────────►│  FIN_WAIT_1
             │◄─────── ACK ────────────────│  CLOSE_WAIT (server)
             │◄─────── FIN ────────────────│  LAST_ACK (server)
             │──────── ACK ───────────────►│
             │                             │
        [TIME_WAIT]                    [CLOSED]
        (chờ ~60s)
```

---

## Ý nghĩa TCP States

| State | Ý nghĩa | Dấu hiệu bất thường |
| :--- | :--- | :--- |
| `ESTABLISHED` | Kết nối đang hoạt động | Quá nhiều = đang có load lớn |
| `LISTEN` | Port mở, sẵn nhận kết nối | Bình thường |
| `SYN_RECV` | Đang trong 3-way handshake | Hàng nghìn = **SYN flood attack** |
| `TIME_WAIT` | Đợi đảm bảo FIN-ACK tới nơi (~60s) | Hàng nghìn = cần tune kernel |
| `CLOSE_WAIT` | Server nhận FIN nhưng app chưa gọi `close()` | **File descriptor leak — app bug** |
| `FIN_WAIT_1/2` | Client đã gửi FIN, đợi server | Tăng liên tục = server chậm phản hồi |
| `LAST_ACK` | Server đã gửi FIN, đợi ACK cuối | Thoáng qua là bình thường |

---

## CLOSE_WAIT — Dấu hiệu app bug

```
CLIENT                      SERVER (app của bạn)
  │──── FIN ──────────────►│   Server nhận FIN → gửi ACK
  │◄─── ACK ───────────────│   State: CLOSE_WAIT
  │                         │
  │        [CHỜ MÃI]        │   ← App KHÔNG gọi close()!
  │                         │   State: vẫn CLOSE_WAIT
```

**Phát hiện CLOSE_WAIT leak:**
```bash
# Đếm số CLOSE_WAIT hiện tại:
ss -tan state close-wait | wc -l

# Nếu số này TĂNG LIÊN TỤC khi chạy nhiều lần → app có bug:
watch -n 1 'ss -tan state close-wait | wc -l'
```

**Nguyên nhân thường gặp:**
- Connection pool không return connection về pool
- Exception handling bỏ qua bước `close()` / `disconnect()`
- HTTP client không gọi `response.close()`

---

## TIME_WAIT — Cần tune khi high load

```bash
# Đếm TIME_WAIT hiện tại:
ss -tan state time-wait | wc -l
```

**TIME_WAIT > 1000** → Cân nhắc tune kernel:

```bash
# Xem setting hiện tại:
sysctl net.ipv4.tcp_tw_reuse
sysctl net.ipv4.ip_local_port_range

# Tune (thêm vào /etc/sysctl.conf):
net.ipv4.tcp_tw_reuse = 1          # Tái sử dụng TIME_WAIT socket
net.ipv4.ip_local_port_range = 1024 65535   # Mở rộng ephemeral ports

# Apply ngay:
sysctl -p
```

> ⚠️ **TIME_WAIT là bình thường** — nó đảm bảo gói tin cũ không bị nhầm với kết nối mới.
> Chỉ tune khi thực sự bị thiếu port (`EADDRINUSE` errors).

---

<!-- _class: divider -->

# 🔧 Phần 4
## Kịch bản thực chiến

---

## Scenario A: "Port 3000 không listen, app có chạy không?"

```bash
# Kiểm tra port cụ thể:
ss -tlnp | grep 3000

# Không có output → app chưa start, hoặc bind sai interface / sai port

# Kiểm tra app có đang chạy bằng tên process:
ss -tlnp | grep -E 'node|python|java|ruby'

# Xem app đang listen port gì:
ss -tlnp | grep $(pgrep -x node)
```

**Checklist debug khi port không listen:**
1. `ps aux | grep app` → App có đang chạy không?
2. `ss -tlnp` → App có bind đúng port không?
3. Xem log app → Có error khi start không?
4. `ss -tlnp | grep '127.0.0.1'` → App bind localhost thay vì `0.0.0.0`?

---

## Scenario B: "MySQL chạy nhưng không connect được từ ngoài"

```bash
ss -tlnp | grep 3306
```

```
State   Recv-Q  Send-Q  Local Address:Port  Peer Address:Port  Process
LISTEN  0       151     127.0.0.1:3306      0.0.0.0:*          mysqld
```

**Vấn đề:** MySQL đang bind `127.0.0.1` — chỉ accept kết nối từ localhost!

**Giải pháp:**
```ini
# /etc/mysql/mysql.conf.d/mysqld.cnf
[mysqld]
bind-address = 0.0.0.0    # Hoặc IP cụ thể của server
```

```bash
# Sau khi restart, kiểm tra lại:
ss -tlnp | grep 3306
# → LISTEN 0 151  0.0.0.0:3306  ← OK
```

> 💡 Pattern tương tự cho Redis (`127.0.0.1:6379`), PostgreSQL (`127.0.0.1:5432`), etc.

---

## Scenario C: "App báo 'too many open files'"

```bash
# Bước 1: Đếm tổng socket đang mở
ss -tan | wc -l

# Bước 2: Tìm leak
ss -tan state close-wait | wc -l   # CLOSE_WAIT không đóng
ss -tan state time-wait | wc -l    # TIME_WAIT tích tụ

# Bước 3: Kiểm tra file descriptor limit
ulimit -n                           # Limit của process hiện tại
cat /proc/sys/fs/file-max           # Limit toàn hệ thống

# Bước 4: Xem process nào đang chiếm nhiều FD nhất
ss -tanp | grep <process-name> | wc -l
```

**Giải pháp theo nguyên nhân:**

| Nguyên nhân | Giải pháp |
| :--- | :--- |
| CLOSE_WAIT nhiều | Fix bug trong app (không đóng connection) |
| TIME_WAIT nhiều | Tune `tcp_tw_reuse`, mở rộng port range |
| Limit quá thấp | Tăng `ulimit -n`, cấu hình `/etc/security/limits.conf` |

---

## Key Takeaways

| Tình huống | Lệnh | Kết luận |
| :--- | :--- | :--- |
| Port có đang listen không? | `ss -tlnp \| grep PORT` | Không có = app chưa start / bind sai |
| App bind đúng interface chưa? | `ss -tlnp \| grep PROCESS` | `127.0.0.1` = chỉ local |
| Có CLOSE_WAIT leak không? | `ss -tan state close-wait \| wc -l` | Tăng liên tục = bug app |
| TIME_WAIT có quá nhiều không? | `ss -tan state time-wait \| wc -l` | >1000 = tune kernel |
| Ai đang kết nối đến DB? | `ss -tnp dport = :5432` | Thấy PID + process name |

**Bộ lệnh cốt lõi:**
```bash
ss -tlnp                    # Lệnh vàng — port nào đang listen
ss -tan state close-wait    # Phát hiện connection leak
ss -tan state time-wait     # Kiểm tra TIME_WAIT tích tụ
ss -tei                     # TCP internals (cwnd, rtt, retrans)
```

---

<!-- _class: title -->

# Cảm ơn đã theo dõi! 🙏

**Network Thực Chiến**


> *"`ss -tlnp` là lệnh đầu tiên khi debug 'tại sao không kết nối được'."*
