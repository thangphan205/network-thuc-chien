# 📡 tcpdump — Bắt gói tin dòng lệnh

`tcpdump` là công cụ capture gói tin ở kernel level. Không có GUI, không tốn nhiều tài nguyên, chạy được trên bất kỳ Linux server nào. Kết quả có thể lưu file `.pcap` để mở trong Wireshark.

---

## ⚙️ Cách hoạt động

`tcpdump` dùng **libpcap** hook vào network interface ở kernel, bắt gói tin trước khi firewall (iptables/nftables) xử lý (ở một số mode). Điều này nghĩa là có thể thấy gói tin **dù firewall drop** nó.

```
Network Interface
       │
   [libpcap] ← tcpdump hook vào đây
       │
  [netfilter/iptables]
       │
  [Socket / Application]
```

---

## 📖 Cheatsheet

### 1. Bắt gói tin cơ bản
```bash
sudo tcpdump -i eth0           # Bắt trên interface eth0
sudo tcpdump -i any            # Bắt trên tất cả interface
sudo tcpdump -i lo             # Bắt localhost traffic (debug IPC)
```

### 2. Filter theo host / network
```bash
sudo tcpdump host 192.168.1.1                    # Đến hoặc từ IP này
sudo tcpdump src host 192.168.1.1                # Chỉ traffic TỪ IP này
sudo tcpdump dst host 192.168.1.1                # Chỉ traffic ĐẾN IP này
sudo tcpdump net 192.168.1.0/24                  # Toàn subnet
```

### 3. Filter theo port / protocol
```bash
sudo tcpdump port 80                             # HTTP
sudo tcpdump port 443                            # HTTPS
sudo tcpdump port 53                             # DNS
sudo tcpdump tcp port 22                         # Chỉ TCP SSH
sudo tcpdump udp port 53                         # Chỉ UDP DNS
sudo tcpdump portrange 8080-8090                 # Port range
```

### 4. Kết hợp filter (Boolean logic)
```bash
sudo tcpdump host 10.0.0.1 and port 80
sudo tcpdump host 10.0.0.1 or host 10.0.0.2
sudo tcpdump not port 22          # Bỏ SSH (giảm noise)
sudo tcpdump "host 10.0.0.1 and (port 80 or port 443)"
```

### 5. Hiển thị dễ đọc hơn
```bash
sudo tcpdump -n               # Không resolve DNS (nhanh hơn, không noise)
sudo tcpdump -nn              # Không resolve DNS lẫn port name
sudo tcpdump -v               # Verbose (thêm TTL, TOS, length)
sudo tcpdump -vvv             # Rất verbose (decode protocol)
sudo tcpdump -A               # In payload dạng ASCII (xem HTTP body)
sudo tcpdump -X               # In payload dạng hex + ASCII
sudo tcpdump -e               # In MAC address (debug L2)
```

### 6. Lưu và đọc file pcap
```bash
# Lưu vào file (gửi cho team, mở Wireshark)
sudo tcpdump -i eth0 -w /tmp/capture.pcap

# Giới hạn số gói / thời gian
sudo tcpdump -i eth0 -c 1000 -w capture.pcap           # Tối đa 1000 gói
sudo tcpdump -i eth0 -G 60 -w capture_%Y%m%d_%H%M%S.pcap  # Rotate mỗi 60s

# Đọc lại file pcap (không cần root)
tcpdump -r capture.pcap
tcpdump -r capture.pcap host 10.0.0.1 port 80   # Filter khi đọc lại
```

### 7. Decode DNS traffic
```bash
sudo tcpdump -nn -i any port 53 -v
# Thấy query và response:
# 10.0.0.5.54321 > 8.8.8.8.53: A? google.com. (28)
# 8.8.8.8.53 > 10.0.0.5.54321: A google.com. 142.250.196.46 (44)
```

### 8. Bắt HTTP traffic (plaintext)
```bash
sudo tcpdump -A -s 0 port 80 | grep -E "GET|POST|Host:|Content-Type:|HTTP/"
# -s 0: capture full packet (không truncate payload)
```

### 9. Detect TCP flags — Debug connection issues
```bash
# Bắt SYN packet (kết nối mới)
sudo tcpdump "tcp[tcpflags] & tcp-syn != 0"

# Bắt RST (connection bị reset — dấu hiệu lỗi)
sudo tcpdump "tcp[tcpflags] & tcp-rst != 0"

# Bắt SYN nhưng không SYN-ACK (port scan hoặc firewall block)
sudo tcpdump "tcp[tcpflags] == tcp-syn"
```

---

## 🔍 Kịch bản thực chiến

### "App không nhận được request, không biết traffic có vào server không?"
```bash
# Bắt trên tất cả interface, lọc theo port app
sudo tcpdump -nn -i any port 8080

# Gửi request từ client → nếu tcpdump thấy gói tin:
# → Traffic đến server rồi, vấn đề ở app level
# → Không thấy gói tin: firewall, routing, hoặc sai IP đích
```

### "Debug mTLS / TLS handshake failure"
```bash
# TLS handshake ở port 443 — dù không decrypt được content, vẫn thấy:
# - ClientHello (cipher suites client support)
# - ServerHello (cipher được chọn)
# - Certificate (server cert)
# - Alert (nếu có lỗi: certificate_unknown, handshake_failure...)
sudo tcpdump -nn -i any port 443 -v -w tls_debug.pcap
# Mở trong Wireshark: Statistics → Expert Information → lọc lỗi
```

### "Debug VXLAN traffic trong Kubernetes"
```bash
# VXLAN dùng UDP port 4789
sudo tcpdump -nn -i any udp port 4789 -v

# Decode inner packet (tcpdump không tự decode VXLAN inner)
# Lưu pcap, mở Wireshark → Analyze → Decode As → VXLAN
sudo tcpdump -i any udp port 4789 -w vxlan_capture.pcap
```

### "Verify firewall rule hoạt động đúng"
```bash
# Terminal 1: Bắt tất cả traffic đến port 80
sudo tcpdump -nn -i eth0 port 80

# Terminal 2: Gửi request
curl http://server_ip/test

# Nếu thấy SYN nhưng không thấy SYN-ACK → firewall drop ở OUTPUT chain
# Nếu không thấy gì → firewall drop ở INPUT chain (gói chưa vào được interface)
# Nếu thấy đủ 3-way handshake → kết nối OK, vấn đề ở application
```

### "Remote capture từ server về máy local (Wireshark)"
```bash
# Trên máy local — pipe tcpdump output từ server về Wireshark
ssh user@server "sudo tcpdump -nn -i eth0 -U -w - port 8080" | wireshark -k -i -

# -U: unbuffered output, -w -: ghi ra stdout
# | wireshark -k -i -: Wireshark đọc từ stdin, mở ngay (-k)
```

---

## 📊 Đọc output tcpdump

```
14:23:45.123456 IP 10.0.0.5.54321 > 10.0.0.10.80: Flags [S], seq 1234567, win 65535, length 0
```

| Phần | Ý nghĩa |
| :--- | :--- |
| `14:23:45.123456` | Timestamp (microsecond precision) |
| `IP` | Protocol L3 (IP, ARP, IPv6...) |
| `10.0.0.5.54321 > 10.0.0.10.80` | Src IP.Port → Dst IP.Port |
| `Flags [S]` | TCP flags: S=SYN, A=ACK, F=FIN, R=RST, P=PSH |
| `seq 1234567` | Sequence number |
| `win 65535` | TCP window size |
| `length 0` | Payload size (0 = chỉ có header, không có data) |

**TCP Flags thường gặp:**
- `[S]` = SYN (mở kết nối)
- `[S.]` = SYN-ACK (server đồng ý)
- `[.]` = ACK (xác nhận)
- `[P.]` = PSH-ACK (gửi data)
- `[F.]` = FIN-ACK (đóng kết nối)
- `[R]` = RST (**kết nối bị reset đột ngột — cần điều tra**)

---

> **Tóm lại:** `tcpdump -nn -i any port X` để xác định traffic có vào server không. `-w file.pcap` để lưu lại phân tích sau. `-A` để xem HTTP body plaintext. RST flag = dấu hiệu lỗi cần điều tra ngay.
