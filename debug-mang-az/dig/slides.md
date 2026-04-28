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

# 🔎 dig
## DNS Debug chuyên nghiệp

**Network Thực Chiến** · Series: Debug Mạng từ A–Z · Tập 05

---

## 📋 Nội dung

1. **dig là gì?** — Tại sao không dùng nslookup
2. **Cấu trúc output** — Đọc từng phần, hiểu STATUS
3. **Query record types** — A, AAAA, MX, NS, TXT, CNAME, SOA
4. **Query DNS server cụ thể** — `@server` và `+short`
5. **`+trace`** — Theo dõi delegation, tìm điểm đứt gãy
6. **TTL & cache** — DNS đang cache ở đâu?
7. **Kịch bản thực chiến** — Website fail, IP cũ, email bounce
8. **Lỗi DNS thường gặp** — NXDOMAIN, SERVFAIL, REFUSED

---

<!-- _class: divider -->

# 🎯 Phần 1
## dig là gì?

---

## dig vs nslookup

Cả hai đều query DNS, nhưng:

| | `nslookup` | `dig` |
|:---|:---|:---|
| **Output** | Khó parse trong script | Có cấu trúc rõ, dễ grep |
| **Record types** | Cơ bản | Đầy đủ (ANY, DNSSEC, SOA...) |
| **Chỉ định DNS server** | `nslookup domain server` | `dig @server domain` |
| **Trace delegation** | ❌ | ✅ `+trace` |
| **Script/automation** | ❌ Unstable output | ✅ `+short` cho output sạch |
| **Status code** | Ẩn | Hiện rõ trong HEADER |

> **Quy tắc:** Dùng `dig` cho mọi việc DNS debug. `nslookup` chỉ có trên Windows hoặc khi `dig` không được cài.

---

## DNS hoạt động thế nào — Nhanh

```
Client hỏi: "google.com là IP nào?"

1. Hỏi /etc/resolv.conf → nameserver 8.8.8.8
2. 8.8.8.8 hỏi root server (.)
3. Root server: "Hỏi .com nameserver"
4. .com nameserver: "Hỏi ns1.google.com"
5. ns1.google.com: "142.250.196.46"
6. 8.8.8.8 cache lại (theo TTL) → trả về client

dig +trace      → thấy từng bước trên
dig @8.8.8.8    → bypass resolv.conf, hỏi thẳng 8.8.8.8
```

---

<!-- _class: divider -->

# 📄 Phần 2
## Cấu trúc Output

---

## Đọc output dig

```bash
dig google.com
```

```
; <<>> DiG 9.18.1 <<>> google.com
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 12345     ← (1) STATUS
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; QUESTION SECTION:
;google.com.                    IN  A                          ← (2) Hỏi gì?

;; ANSWER SECTION:
google.com.             300     IN  A  142.250.196.46          ← (3) Trả lời + TTL

;; Query time: 12 msec
;; SERVER: 8.8.8.8#53                                          ← (4) DNS server dùng
;; WHEN: Thu Apr 24 10:00:00 2026
;; MSG SIZE  rcvd: 55
```

---

## Đọc STATUS — Quan trọng nhất

Status nằm trong dòng `HEADER`, quyết định hướng debug tiếp theo:

| Status | Nghĩa | Hành động |
|:---|:---|:---|
| `NOERROR` | Query thành công | Đọc ANSWER SECTION |
| `NXDOMAIN` | Domain không tồn tại | Kiểm tra typo, `dig +trace` |
| `SERVFAIL` | DNS server lỗi hoặc DNSSEC fail | `dig @8.8.8.8`, `dig +trace` |
| `REFUSED` | Server từ chối query (ACL) | Thử DNS server khác |
| `NOERROR` + ANSWER trống | Domain tồn tại nhưng không có record loại đó | Query đúng record type chưa? |

> **Thói quen tốt:** Nhìn STATUS trước, rồi mới đọc ANSWER SECTION.

---

<!-- _class: divider -->

# 📋 Phần 3
## Record Types

---

## Query các record type

```bash
dig google.com A          # IPv4 — mặc định nếu không chỉ định type
dig google.com AAAA       # IPv6
dig google.com MX         # Mail server (kèm priority)
dig google.com NS         # Authoritative nameserver của domain
dig google.com TXT        # Text record (SPF, DKIM, xác minh domain)
dig google.com CNAME      # Alias → trỏ đến domain khác
dig google.com SOA        # Start of Authority: serial, refresh, expire, TTL min
dig google.com PTR        # Reverse lookup (thường dùng với -x)
```

**Reverse DNS lookup:**
```bash
dig -x 8.8.8.8 +short
# dns.google.

# Hoặc trực tiếp:
dig +short -x 142.250.196.46
# lax17s55-in-f14.1e100.net.
```

---

## Record type quan trọng trong thực chiến

### MX — Debug email bounce
```bash
dig gmail.com MX +short
# 5 gmail-smtp-in.l.google.com.
# 10 alt1.gmail-smtp-in.l.google.com.
# ↑ Priority (số nhỏ = ưu tiên cao hơn)
```

### TXT — SPF / DKIM / domain verification
```bash
dig gmail.com TXT +short | grep spf
# "v=spf1 redirect=_spf.google.com"
dig google._domainkey.gmail.com TXT +short
# "v=DKIM1; k=rsa; p=MIIBIjAN..."
```

### NS — Ai đang quản lý DNS zone này?
```bash
dig google.com NS +short
# ns1.google.com.
# ns2.google.com.
# ns3.google.com.
# ns4.google.com.
```

---

<!-- _class: divider -->

# 🎯 Phần 4
## Query DNS Server Cụ Thể & Short Output

---

## `@server` — Bypass DNS mặc định

```bash
# Hỏi Google Public DNS
dig @8.8.8.8 google.com

# Hỏi Cloudflare DNS
dig @1.1.1.1 google.com

# Hỏi DNS nội bộ (khi debug internal domain)
dig @192.168.1.1 internal.corp.com

# Hỏi thẳng authoritative nameserver (bypass cache)
dig @ns1.google.com google.com
```

**Tại sao cần `@server`?**

```
dig domain          → Hỏi DNS trong /etc/resolv.conf (có thể bị cache, bị filter)
dig @8.8.8.8 domain → Bypass resolver nội bộ → loại trừ lỗi DNS ISP/công ty
dig @ns1.example.com domain → Query trực tiếp authoritative → loại trừ propagation delay
```

---

## `+short` — Output sạch cho script

```bash
# Chỉ in IP, không có metadata
dig +short google.com
# 142.250.196.46

# Dùng trong script / variable
IP=$(dig +short api.example.com | head -1)
echo "Connecting to $IP"

# MX ngắn gọn
dig +short gmail.com MX
# 5 gmail-smtp-in.l.google.com.
# 10 alt1.gmail-smtp-in.l.google.com.

# NS ngắn gọn
dig +short google.com NS
# ns1.google.com.
# ns2.google.com.
```

> `+short` bỏ tất cả section, chỉ giữ answer value. Dùng `| head -1` khi domain có nhiều A record.

---

<!-- _class: divider -->

# 🔍 Phần 5
## `+trace` — Theo Dõi Delegation

---

## `+trace` — Tìm điểm đứt gãy DNS

`dig +trace` không hỏi resolver — nó tự mình trace từ root xuống, từng bước delegation.

```bash
dig +trace example.com
```

```
.                       518400  IN  NS  a.root-servers.net.   ← (1) Root servers
a.root-servers.net.     ...

com.                    172800  IN  NS  a.gtld-servers.net.   ← (2) .com TLD
a.gtld-servers.net.     ...

example.com.            172800  IN  NS  ns1.example.com.      ← (3) Authoritative NS
ns1.example.com.        ...

example.com.            3600    IN  A   93.184.216.34         ← (4) Final answer
```

---

## Đọc kết quả `+trace`

**Khi nào `+trace` hữu ích?**

```
NXDOMAIN từ resolver nội bộ
  → dig +trace domain
  → Nếu trace thành công → vấn đề ở resolver nội bộ, không phải domain
  → Nếu trace fail ở bước nào → nameserver tại bước đó có vấn đề

Mới update DNS record nhưng vẫn thấy IP cũ
  → dig @8.8.8.8 domain      → IP mới? → Cache ở resolver nội bộ
  → dig @ns1.domain domain   → IP cũ?  → Authoritative chưa update
  → dig +trace domain        → Xem từng hop đang trả về gì
```

> ⚠️ `+trace` gửi query đến root server thực — không dùng cho internal-only domain (sẽ fail tại bước delegation về TLD thật).

---

<!-- _class: divider -->

# ⏱️ Phần 6
## TTL & Cache

---

## Đọc TTL — DNS đang cache ở đâu?

```bash
dig google.com | grep -A2 "ANSWER SECTION"
```

```
;; ANSWER SECTION:
google.com.     253     IN  A  142.250.196.46
                ^^^
                TTL còn lại: 253 giây
```

**Phân tích TTL:**

| TTL quan sát | Nghĩa |
|:---|:---|
| TTL = max (vd 300) mỗi lần query | Cache đã expire, đang query fresh |
| TTL giảm dần mỗi lần query | Record đang được cache, đếm ngược đến 0 |
| TTL = 0 | Record vừa được cache hoặc không cache |

---
**Flush cache khi cần:**
```bash
# Linux (systemd-resolved)
sudo resolvectl flush-caches

# macOS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

```powershell
# Windows / Windows Server (cmd hoặc PowerShell)
ipconfig /flushdns

# Windows Server — flush DNS Server cache (nếu máy chạy DNS Server role)
Clear-DnsServerCache -Force
```

---

<!-- _class: divider -->

# 🔧 Phần 7
## Kịch bản thực chiến

---

## Scenario A: "Website không resolve, không biết lỗi DNS hay app"

```bash
# Bước 1: Test với Google DNS → loại trừ ISP/resolver nội bộ
dig @8.8.8.8 example.com +short
# Có IP → DNS root/TLD OK, vấn đề ở resolver nội bộ hoặc app

# Bước 2: Lấy authoritative NS, query thẳng
dig NS example.com +short
# ns1.example.com.

dig @ns1.example.com example.com +short
# Có IP → record đã được set đúng, vấn đề là propagation delay
# NXDOMAIN → record chưa được tạo trên authoritative server

# Bước 3: Trace nếu vẫn không rõ
dig +trace example.com
# Xem bị "stuck" ở delegation nào
```

---

## Scenario B: "DNS update rồi nhưng client vẫn thấy IP cũ"

```bash
# Kiểm tra TTL còn lại
dig example.com | grep "IN A"
# example.com. 58 IN A 1.2.3.4 ← còn cache 58 giây

# So sánh: resolver nội bộ vs authoritative
dig example.com +short            # IP cũ: 1.2.3.4
dig @ns1.example.com example.com +short  # IP mới: 5.6.7.8
# → Authoritative đã update, đang chờ cache expire

# Chờ hoặc flush:
sudo resolvectl flush-caches                                     # Linux
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder   # macOS
ipconfig /flushdns                                               # Windows
```

---

## Scenario C: "Email bị bounce, kiểm tra MX"

```bash
# Xem mail server của domain
dig gmail.com MX +short
# 5 gmail-smtp-in.l.google.com.
# 10 alt1.gmail-smtp-in.l.google.com.

# Kiểm tra SPF — ai được phép gửi mail thay mặt domain này?
dig gmail.com TXT +short | grep spf
# "v=spf1 redirect=_spf.google.com"

# Kiểm tra DKIM
dig google._domainkey.gmail.com TXT +short
# "v=DKIM1; k=rsa; p=..."

# Nếu MX trống hoặc NXDOMAIN → domain chưa cấu hình nhận mail
# Nếu SPF không có IP gửi thật → mail bị reject/spam
```

---

<!-- _class: divider -->

# ⚠️ Phần 8
## Lỗi DNS thường gặp

---

## Bảng lỗi DNS + cách debug

| Status | Nguyên nhân thường gặp | Debug |
|:---|:---|:---|
| `NXDOMAIN` | Domain không tồn tại, typo, chưa propagate | `dig +trace domain` |
| `SERVFAIL` | Authoritative server lỗi hoặc DNSSEC fail | `dig @8.8.8.8 domain`, `dig +trace` |
| `REFUSED` | DNS server từ chối (ACL / firewall) | `dig @1.1.1.1 domain` |
| Timeout | DNS server không reach được | `ping dns_server_ip`, `nc -zuv dns 53` |
| NOERROR + no answer | Domain tồn tại, không có record type đó | Query đúng type chưa? |
| Query time cao | Resolver chậm / xa | `dig @8.8.8.8` so sánh |

---

## Cheatsheet — 3 lệnh giải quyết 90% bài toán DNS

```bash
# 1. Lấy IP nhanh
dig +short domain

# 2. Loại trừ DNS nội bộ (so sánh với Google DNS)
dig @8.8.8.8 domain +short

# 3. Tìm điểm đứt gãy trong DNS delegation
dig +trace domain
```

**Bộ đầy đủ:**
```bash
dig +short domain                      # IP nhanh
dig @8.8.8.8 domain +short            # Bypass resolver nội bộ
dig @ns1.domain domain +short         # Hỏi thẳng authoritative
dig +trace domain                      # Trace từng bước delegation
dig domain MX/NS/TXT +short           # Query record type cụ thể
dig -x ip +short                       # Reverse lookup
```

---

<!-- _class: title -->

# Cảm ơn đã theo dõi! 🙏

**Network Thực Chiến**

Tập tiếp theo: **curl — HTTP Debug từ terminal**

> *"`dig @8.8.8.8 domain` loại trừ DNS nội bộ. `dig +trace domain` tìm đúng tầng delegation bị lỗi."*
