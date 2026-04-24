# 🔎 dig — DNS Debug chuyên nghiệp

`dig` (Domain Information Groper) là công cụ query DNS mạnh nhất. Khác với `nslookup` (giao diện cũ, kết quả khó đọc trong script), `dig` trả về output có cấu trúc rõ ràng, hỗ trợ tất cả record types, và cực kỳ mạnh khi trace vấn đề DNS.

---

## ⚙️ Cấu trúc output của dig

```bash
dig google.com
```
```
; <<>> DiG 9.18.1 <<>> google.com
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 12345
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; QUESTION SECTION:
;google.com.                    IN  A           ← Hỏi: A record của google.com?

;; ANSWER SECTION:
google.com.             300     IN  A  142.250.196.46   ← Trả lời: IP + TTL còn lại (300s)

;; Query time: 12 msec
;; SERVER: 8.8.8.8#53            ← DNS server đã trả lời
;; WHEN: Thu Apr 24 10:00:00 2026
;; MSG SIZE  rcvd: 55
```

**Đọc STATUS:** `NOERROR` = OK, `NXDOMAIN` = domain không tồn tại, `SERVFAIL` = DNS server lỗi, `REFUSED` = server từ chối query.

---

## 📖 Cheatsheet

### 1. Query các record type khác nhau
```bash
dig google.com A          # IPv4 address (mặc định)
dig google.com AAAA       # IPv6 address
dig google.com MX         # Mail server
dig google.com NS         # Authoritative nameserver
dig google.com TXT        # Text record (SPF, DKIM, verification)
dig google.com CNAME      # Alias
dig google.com SOA        # Start of Authority (serial, refresh, expire)
dig google.com ANY        # Tất cả record (nhiều server không hỗ trợ nữa)
```

### 2. Query đến DNS server cụ thể
```bash
# Dùng @ để chỉ định DNS server
dig @8.8.8.8 google.com         # Hỏi Google DNS
dig @1.1.1.1 google.com         # Hỏi Cloudflare DNS
dig @192.168.1.1 internal.host  # Hỏi DNS nội bộ
dig @ns1.example.com google.com # Hỏi thẳng authoritative server
```

### 3. Output ngắn gọn — Dùng trong script
```bash
dig +short google.com
# 142.250.196.46  ← Chỉ in IP, không có metadata

dig +short google.com MX
# 10 smtp.google.com.
# 20 smtp2.google.com.

dig +short -x 8.8.8.8       # Reverse DNS lookup (PTR record)
# dns.google.
```

### 4. Trace DNS delegation — Tìm đứt gãy
```bash
dig +trace google.com
# Bắt đầu từ root nameserver (.), trace từng bước delegation:
# . → .com → google.com → answer
# Nếu bị "stuck" ở bước nào → nameserver đó có vấn đề
```

### 5. Kiểm tra TTL — DNS có đang cache không?
```bash
dig google.com | grep -A2 "ANSWER SECTION"
# google.com. 253 IN A 142.250.196.46
#              ^^^
# TTL còn lại 253 giây → record đang được cache
# Nếu TTL = 300 mỗi lần query → cache đã expire, đang query fresh
```

### 6. Debug trong Kubernetes — Query CoreDNS
```bash
# Từ trong Pod:
dig kubernetes.default.svc.cluster.local
dig my-service.my-namespace.svc.cluster.local

# Query thẳng CoreDNS IP (thường là 10.96.0.10)
dig @10.96.0.10 my-service.default.svc.cluster.local

# Kiểm tra ndots config (quan trọng cho K8s DNS resolution)
cat /etc/resolv.conf
# nameserver 10.96.0.10
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5   ← 5 dot mới dùng absolute name
```

### 7. DNSSEC validation
```bash
dig +dnssec google.com
# Nếu RRSIG xuất hiện → DNSSEC được ký
# Nếu AD flag trong HEADER → response đã được validated
```

---

## 🔍 Kịch bản thực chiến

### "Website không resolve được, không biết lỗi DNS hay app?"
```bash
# Bước 1: Test với Google DNS (loại trừ ISP DNS)
dig @8.8.8.8 example.com +short
# Có IP → DNS root/TLD OK, vấn đề ở DNS nội bộ/ISP

# Bước 2: Test với authoritative server trực tiếp
dig NS example.com +short          # Lấy authoritative nameserver
dig @ns1.example.com example.com   # Query thẳng → loại trừ propagation delay

# Bước 3: Trace nếu vẫn không rõ
dig +trace example.com
```

### "DNS đã update nhưng client vẫn thấy IP cũ"
```bash
# Kiểm tra TTL còn lại
dig example.com | grep "IN A"
# example.com. 58 IN A 1.2.3.4 ← còn 58 giây cache
# Chờ hết TTL hoặc flush local DNS cache:

# Linux (systemd-resolved):
sudo systemd-resolve --flush-caches

# macOS:
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### "Service trong K8s không tìm thấy nhau qua tên"
```bash
# Từ trong Pod:
dig kubernetes.default.svc.cluster.local
# NXDOMAIN → CoreDNS bị lỗi hoặc service không tồn tại

# Kiểm tra CoreDNS đang chạy:
kubectl get pods -n kube-system | grep coredns

# Test search domain:
dig my-service                               # Phụ thuộc ndots
dig my-service.default.svc.cluster.local.    # FQDN với trailing dot → luôn absolute
```

### "Email bị bounce, kiểm tra MX record"
```bash
dig gmail.com MX +short
# 5 gmail-smtp-in.l.google.com.
# 10 alt1.gmail-smtp-in.l.google.com.

# Kiểm tra SPF (chống spam giả mạo):
dig gmail.com TXT +short | grep spf
# "v=spf1 redirect=_spf.google.com"
```

---

## ⚠️ Các lỗi DNS thường gặp

| Status | Nguyên nhân thường gặp | Cách debug |
| :--- | :--- | :--- |
| `NXDOMAIN` | Domain không tồn tại hoặc typo | `dig +trace domain` để xem từng bước |
| `SERVFAIL` | Authoritative server lỗi / DNSSEC fail | `dig @8.8.8.8 domain` và `dig +trace` |
| `REFUSED` | DNS server từ chối query (ACL) | Thử DNS server khác |
| Timeout | DNS server không reach được | `ping dns_server_ip` trước |
| Query time cao | DNS server chậm hoặc xa | Đổi resolver hoặc cache locally |

---

> **Tóm lại:** `dig +short domain` cho IP nhanh. `dig @8.8.8.8 domain` để loại trừ DNS nội bộ. `dig +trace domain` để tìm đúng tầng delegation bị lỗi. Ba lệnh này giải quyết được 90% bài toán DNS.
