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
  table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
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
  section.title h1 { font-size: 2.6em; color: #63b3ed; border: none; }
  section.title h2 { font-size: 1.2em; color: #68d391; border: none; margin-top: 0.2em; }
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
  section.divider h2 { border: none; color: #a0aec0; }
  .tag-l1 { color: #fc8181; font-weight: bold; }
  .tag-l2 { color: #f6ad55; font-weight: bold; }
  .tag-l3 { color: #68d391; font-weight: bold; }
  .tag-l4 { color: #63b3ed; font-weight: bold; }
  .tag-l7 { color: #b794f4; font-weight: bold; }
---

<!-- _class: title -->

# Debug Mạng từ A–Z
## Hệ thống hóa kỹ năng chẩn đoán mạng

**Network Thực Chiến** · Series tổng hợp · 11 tập · 7 module

---

## Tại sao cần một series về debug mạng?

Khi mạng có vấn đề, hầu hết kỹ sư làm gì?

```
❌ Google "why is ping slow"
❌ Restart service và cầu may
❌ "Mình không biết, check lại firewall đi"
❌ Hỏi đồng nghiệp mà ai cũng đoán mò
```

**Vấn đề:** Không phải thiếu tool — mà thiếu **phương pháp**.

> Một kỹ sư mạng giỏi không đoán mò — họ có **methodology**, có **công cụ**, và biết hỏi đúng câu hỏi ở đúng tầng OSI.

---

## Nội dung series

1. **Methodology** — Tư duy debug có hệ thống
2. **OSI Debug Map** — Mỗi tầng, một câu hỏi, một công cụ
3. **7 Module · 11 Tập** — Từ `ping` đến Kubernetes eBPF
4. **Lộ trình học** — Người mới → Kỹ sư nâng cao → K8s Engineer
5. **Kịch bản thực chiến** — 3 scenario ghép nhiều công cụ

---

<!-- _class: divider -->

# Phần 1
## Methodology: Tư duy trước, tool sau

---

## Quy trình debug 5 bước

Áp dụng cho **mọi sự cố mạng** — từ ping không tới đến K8s pod mất kết nối:

```
Bước 1 — XÁC ĐỊNH TRIỆU CHỨNG
         "Cái gì bị lỗi? Từ đâu? Đến đâu? Từ khi nào?"

Bước 2 — ĐẶT GIẢ THUYẾT
         "Tầng OSI nào có thể gây ra lỗi này?"

Bước 3 — TEST VÀ LOẠI TRỪ
         Dùng tool phù hợp, test từng tầng — không nhảy cóc

Bước 4 — TÌM ĐIỂM PHÂN GIỚI
         "Từ đây hoạt động, từ đây không → root cause nằm ở giữa"

Bước 5 — XÁC NHẬN VÀ DOCUMENT
         Ghi root cause, fix, cách phòng ngừa
```

---

## OSI Model — Góc nhìn debug thực tế

| Tầng | Câu hỏi cần trả lời | Công cụ |
| :--- | :--- | :--- |
| **L1 — Physical** | Cáp có cắm? NIC có up? | `ip link`, `ethtool` |
| **L2 — Data Link** | ARP resolve được không? MAC đúng không? | `arp`, `ip neigh`, `tcpdump` |
| **L3 — Network** | Route đúng không? Ping tới không? Mất gói ở đâu? | `ping`, `mtr`, `ip route` |
| **L4 — Transport** | Port có mở? TCP handshake thành công không? | `ss`, `nc`, `tcpdump` |
| **L5–6 — Session/TLS** | TLS cert hợp lệ không? Handshake lỗi ở đâu? | `openssl s_client`, `curl -v` |
| **L7 — Application** | DNS resolve đúng? HTTP trả gì? App lỗi gì? | `dig`, `curl`, `tcpdump port 80` |

> **Quy tắc vàng:** Debug **từ dưới lên** (L1 → L7).
> Đừng debug DNS khi `ping` còn không tới được.

---

<!-- _class: divider -->

# Phần 2
## Bản đồ 7 Module · 11 Tập

---

## Module 1–2: Connectivity & Transport

| Tập | Tool | Mô tả ngắn |
| :--- | :--- | :--- |
| **01** | `ping` | ICMP, MTU Discovery, TTL Fingerprinting, Flood Ping |
| **02** | `mtr` | Kết hợp ping + traceroute — đọc StDev, phát hiện bottleneck |
| **03** | `ss` | Thay thế `netstat` — TCP states, port leak, connection tracking |
| **04** | `netcat (nc)` | Dao Thụy Sĩ TCP/UDP — test port, tạo server tạm, debug firewall |

**Học xong Module 1–2:** Kiểm tra được kết nối từ L3 đến L4 mà không cần GUI.

---

## Module 3–5: DNS, HTTP, Packet Capture

| Tập | Tool | Mô tả ngắn |
| :--- | :--- | :--- |
| **05** | `dig` | Query types, trace delegation, debug K8s CoreDNS, flush TTL |
| **06** | `curl` | Headers, auth, TLS cert, redirect chain, timing breakdown |
| **07** | `tcpdump` | Filter syntax, bắt ra file, decode TCP flags, remote capture |
| **08** | `Wireshark` | Remote capture từ server, follow TCP stream, decode protocol |

**Học xong Module 3–5:** Nhìn thấy gói tin thực tế đi từ client đến server.

---

## Module 6–7: Performance & Kubernetes

| Tập | Tool | Mô tả ngắn |
| :--- | :--- | :--- |
| **09** | `iPerf3` | TCP/UDP throughput, jitter, parallel streams, JSON output |
| **10** | `netshoot` | Pod network debug, capture trong container, tcpdump + mtr trong K8s |
| **11** | `Hubble / Inspektor Gadget` | eBPF-based observability, Layer 7 tracing trong K8s |

**Học xong Module 6–7:** Benchmark được hiệu năng mạng và debug được sự cố trong môi trường container/K8s.

---

<!-- _class: divider -->

# Phần 3
## Lộ trình học

---

## Chọn lộ trình phù hợp

**Người mới bắt đầu — Xây nền vững:**
```
Tập 01 (ping) → Tập 02 (mtr) → Tập 03 (ss) → Tập 05 (dig)
```
Nắm được 80% sự cố mạng thông thường.

**Kỹ sư muốn nâng cấp — Đào sâu hơn:**
```
Tập 04 (nc) → Tập 06 (curl) → Tập 07 (tcpdump) → Tập 08 (Wireshark)
```
Debug được từ L4 lên L7, nhìn thấy gói tin.

**Kỹ sư K8s / Cloud Native — Full stack:**
```
Toàn bộ Module 1–6 → Tập 09 (iPerf3) → Tập 10 (netshoot) → Tập 11 (eBPF)
```
Debug được mọi tầng — từ NIC đến application trong container.

---

<!-- _class: divider -->

# Phần 4
## Kịch bản thực chiến

---

## Scenario A: "Website load chậm, không biết lỗi ở đâu"

Phương pháp điều tra từ dưới lên:

```bash
# L3 — Có tới không? Latency cao không?
ping google.com

# L3 — Bottleneck ở hop nào? Mất gói ở đâu?
mtr -rw google.com

# L7 — DNS resolve đúng không? TTL còn bao lâu?
dig google.com

# L7 — HTTP layer trả gì? Redirect không? TLS lỗi không?
curl -v https://google.com

# L4/L7 — Gói tin thực tế ra sao?
tcpdump -i eth0 port 80 or port 443
```

---

## Scenario B: "Microservice A không kết nối được Service B"

```bash
# L4 — Port B có đang listen không?
ss -tlnp | grep <port>

# L4 — Firewall / NetworkPolicy có chặn không?
nc -zv <service-B> <port>

# L7 — DNS trong cluster có resolve không?
dig <service-B>.<namespace>.svc.cluster.local

# L7 — App có trả lời không? Health check ra sao?
curl http://<service-B>:<port>/health
```

**K8s bonus:** Nếu vẫn không được → `netshoot` pod, tcpdump trên node.

---

## Scenario C: "Throughput mạng thấp hơn mong đợi"

```bash
# L3 — MTU có bị cắt không? (1500 - 20 IP - 8 ICMP = 1472)
ping -s 1472 -M do <host>

# L3 — Path có packet loss không? Jitter cao không?
mtr -r <host>

# L6 — Thực tế đạt bao nhiêu Mbps?
iperf3 -c <server> -t 30 -P 4

# L4 — TCP window scaling, retransmit có không?
tcpdump -w capture.pcap host <server>
# → Mở Wireshark: Statistics > TCP Stream Graphs
```

---

## Key Takeaways

**3 nguyên tắc:**

1. **Methodology trước** — Không đoán mò, debug từ L1 lên L7
2. **Tool đúng tầng** — `ping` cho L3, `ss` cho L4, `dig` cho DNS, `curl` cho HTTP
3. **Kết hợp tool** — Sự cố thực tế cần nhiều tool phối hợp, không một tool nào đủ

**Bộ công cụ cốt lõi cần nắm:**
```
ping  →  mtr  →  ss  →  nc  →  dig  →  curl  →  tcpdump
 L3       L3     L4    L4    L7      L7       L3–L7
```

> Nắm 7 tool này → xử lý được 95% sự cố mạng gặp trong thực tế.

---

<!-- _class: title -->

# Bắt đầu từ Tập 01

**Network Thực Chiến**

> *"Debug không phải là may mắn — đó là phương pháp."*
