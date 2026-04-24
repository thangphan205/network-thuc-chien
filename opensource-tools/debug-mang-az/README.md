# 🔍 Debug Mạng từ A-Z — Lộ trình học toàn diện

> **Triết lý:** Một kỹ sư mạng giỏi không cần đoán mò — họ có phương pháp, có công cụ, và biết hỏi đúng câu hỏi ở đúng tầng OSI.

Series này xây dựng bộ kỹ năng **chẩn đoán mạng có hệ thống** — từ kiểm tra kết nối cơ bản đến bắt gói tin, phân tích DNS, benchmark hiệu năng, và debug trong môi trường Kubernetes.

---

## 🧠 Tư duy nền tảng: Methodology trước, Tool sau

Trước khi đụng vào bất kỳ công cụ nào, cần nắm vững **quy trình debug**:

```
1. XÁC ĐỊNH TRIỆU CHỨNG       → "Cái gì bị lỗi? Từ đâu? Đến đâu?"
2. ĐẶT GIẢ THUYẾT             → "Tầng nào có thể gây ra lỗi này?"
3. TEST VÀ LOẠI TRỪ           → Dùng tool phù hợp, test từng tầng
4. TÌM ĐIỂM PHÂN GIỚI         → "Từ đây hoạt động, từ đây không"
5. XÁC NHẬN VÀ DOCUMENT       → Ghi lại root cause, fix, và cách phòng ngừa
```

### OSI Model — Góc nhìn debug (không phải lý thuyết)

| Tầng | Câu hỏi debug | Công cụ |
| :--- | :--- | :--- |
| **L1 — Physical** | Cáp có cắm không? NIC có up không? | `ip link`, `ethtool` |
| **L2 — Data Link** | ARP có resolve không? MAC đúng không? | `arp`, `ip neigh`, `tcpdump` |
| **L3 — Network** | Route có đúng không? Ping có tới không? | `ping`, `mtr`, `ip route` |
| **L4 — Transport** | Port có mở không? Kết nối TCP có thiết lập không? | `ss`, `nc`, `curl` |
| **L5-6 — Session/Pres** | TLS cert có hợp lệ không? | `openssl s_client`, `curl -v` |
| **L7 — Application** | DNS resolve đúng không? HTTP trả về gì? | `dig`, `curl`, `tcpdump port 80` |

> **Quy tắc vàng:** Debug **từ dưới lên** (L1 → L7). Đừng debug DNS khi `ping` còn không tới được.

---

## 📚 Danh sách tập (Episodes)

### Module 1 — Connectivity: Kiểm tra kết nối

| Tập | Chủ đề | Mô tả | Tài liệu |
| :--- | :--- | :--- | :--- |
| **01** | **ping — Nâng cao** | ICMP, MTU Discovery, TTL Fingerprinting, Flood Ping | [📂 `../ping`](../ping) |
| **02** | **mtr — Chẩn đoán đường đi** | Kết hợp ping + traceroute, đọc StDev, phát hiện bottleneck | [📂 `../mtr`](../mtr) |

### Module 2 — Sockets & Ports: Kiểm tra kết nối Transport

| Tập | Chủ đề | Mô tả | Tài liệu |
| :--- | :--- | :--- | :--- |
| **03** | **ss — Trạng thái socket** | Thay thế `netstat`, đọc TCP states, tìm port leak, connection tracking | [📂 `../ss`](../ss) |
| **04** | **netcat (nc) — Dao Thụy Sĩ TCP/UDP** | Test port, tạo server tạm, transfer file, debug firewall rule | [📂 `../netcat`](../netcat) |

### Module 3 — DNS: Chẩn đoán phân giải tên miền

| Tập | Chủ đề | Mô tả | Tài liệu |
| :--- | :--- | :--- | :--- |
| **05** | **dig — DNS Debug chuyên nghiệp** | Query types, trace delegation, DNSSEC, TTL flush, common DNS failures | [📂 `../dig`](../dig) |

### Module 4 — Application: HTTP & TLS

| Tập | Chủ đề | Mô tả | Tài liệu |
| :--- | :--- | :--- | :--- |
| **06** | **curl — HTTP Debug từ terminal** | Headers, auth, TLS cert, redirect chain, timing breakdown, proxy debug | [📂 `../curl`](../curl) |

### Module 5 — Packet Capture: Nhìn thấy gói tin

| Tập | Chủ đề | Mô tả | Tài liệu |
| :--- | :--- | :--- | :--- |
| **07** | **tcpdump — Bắt gói tin dòng lệnh** | Filter syntax, capture to file, decode TLS handshake, phân tích TCP flags | [📂 `../tcpdump`](../tcpdump) |
| **08** | **Wireshark — Phân tích GUI** | Remote capture từ server, follow TCP stream, decode protocol | *(Đang cập nhật)* |

### Module 6 — Performance: Đo hiệu năng

| Tập | Chủ đề | Mô tả | Tài liệu |
| :--- | :--- | :--- | :--- |
| **09** | **iPerf3 — Benchmark băng thông** | TCP/UDP throughput, jitter, multiple streams, kết quả JSON | [📂 `../iperf3`](../iperf3) |

### Module 7 — Kubernetes: Debug mạng trong K8s

| Tập | Chủ đề | Mô tả | Tài liệu |
| :--- | :--- | :--- | :--- |
| **10** | **netshoot — Container debug** | Pod network debug, capture trong container, kết hợp tcpdump + mtr trong K8s | *(Đang cập nhật)* |
| **11** | **Hubble / Inspektor Gadget** | eBPF-based observability, Layer 7 tracing trong K8s | *(Đang cập nhật)* |

---

## 🗺 Lộ trình học đề xuất

```
NGƯỜI MỚI BẮT ĐẦU
    → Tập 01 (ping) → Tập 02 (mtr) → Tập 03 (ss) → Tập 05 (dig)

KỸ SƯ MUỐN NÂNG CẤP
    → Tập 04 (nc) → Tập 06 (curl) → Tập 07 (tcpdump)

KỸ SƯ K8S / CLOUD
    → Tất cả Module 1-6 → Tập 10 (netshoot) → Tập 11 (eBPF)
```

---

## 🔗 Kịch bản thực chiến xuyên series

Các tình huống thực tế dùng nhiều công cụ phối hợp:

### Scenario A: "Website load chậm, không biết lỗi ở đâu"
```
ping host         → Có tới không? Latency cao không?
mtr host          → Bottleneck ở hop nào?
dig host          → DNS có đúng không?
curl -v host      → HTTP layer có lỗi không?
tcpdump port 80   → Gói tin thực tế ra sao?
```

### Scenario B: "Microservice A không kết nối được Service B"
```
ss -tlnp          → Port B có listen không?
nc -zv B port     → Firewall/NetworkPolicy có chặn không?
dig B.namespace   → DNS trong cluster có resolve không?
curl B:port/health → App có trả lời không?
```

### Scenario C: "Throughput mạng thấp hơn mong đợi"
```
ping -s 1472 -M do → MTU có bị cắt không?
mtr -r             → Path có packet loss không?
iperf3             → Thực tế đạt bao nhiêu Mbps?
tcpdump            → TCP window scaling, retransmit có không?
```

---

> 💡 **Tip:** Bookmark trang này. Mỗi khi gặp sự cố mạng, quay lại đây chọn đúng công cụ thay vì Google lung tung.
