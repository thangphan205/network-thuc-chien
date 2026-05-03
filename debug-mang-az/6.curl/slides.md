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
---

<!-- _class: title -->

# 🌐 curl 
## HTTP Debug từ terminal chuyên nghiệp

**Network Thực Chiến** · Series: Debug Mạng từ A–Z · Tập 06

---

## 📋 Nội dung

1. **Cơ bản** — Headers, Redirect & Custom Request
2. **Nâng cao** — Phân tích hiệu năng (Timing) & TLS Debug
3. **Kịch bản thực chiến** — Lỗi xác thực, CDN
4. **Bảng tra cứu** — Ý nghĩa HTTP Status Code khi debug

> `curl` không chỉ để tải file. Trong tay kỹ sư, nó là công cụ phân tích HTTP/HTTPS đầy đủ nhất!

---

<!-- _class: divider -->

# 🚀 Phần 1
## Thao tác HTTP cơ bản

---

## 1. Xem Headers & Theo dõi Redirect

Dùng `curl` để kiểm tra nhanh response headers và hành vi redirect của server.

### Chỉ lấy Headers (`-I`)
```bash
curl -I https://example.com
# Sử dụng HEAD method, lấy headers mà không tải body. Rất nhẹ & nhanh.
```

### Theo dõi chuỗi Redirect (`-L`)
```bash
curl -L https://example.com
# -L: Follow redirect (ví dụ: HTTP 301 sang HTTPS)

curl -v -L https://example.com 2>&1 | grep -E "< HTTP|Location:|> GET"
# Thấy toàn bộ luồng nhảy trang.
```

---

## 2. Phân tích chi tiết với Verbose Mode (`-v`)

```bash
curl -v https://example.com
```

**Verbose (`-v`) cho thấy gì?**
- `*` : Quá trình phân giải DNS & TLS handshake
- `>` : Các Request headers được gửi đi
- `<` : Các Response headers nhận về

*Dùng `-v` là bước đầu tiên khi muốn biết "server đang nói chuyện thế nào với client".*

---

## 3. Custom Headers & POST Request

Test API với các thông số xác thực hoặc nội dung JSON.

### Thêm Custom Headers (`-H`)
```bash
curl -H "Authorization: Bearer token123" https://api.example.com/v1/users
curl -H "Cache-Control: no-cache" https://example.com   # Bỏ qua CDN cache
```

### POST Data (`-d`) & HTTP Method (`-X`)
```bash
curl -X POST https://api.example.com/v1/items \
  -H "Content-Type: application/json" \
  -d '{"name": "test", "value": 42}'
```

---

<!-- _class: divider -->

# ⏱️ Phần 2
## Hiệu năng (Timing) & TLS Debug

---

## 4. Phân tích Timing — Tìm bottleneck

API chậm? Hãy dùng `-w` (write-out) để đo thời gian từng giai đoạn:

```bash
curl -o /dev/null -s -w "\
namelookup:    %{time_namelookup}s\n\
connect:       %{time_connect}s\n\
tls_handshake: %{time_appconnect}s\n\
ttfb:          %{time_starttransfer}s\n\
total:         %{time_total}s\n\
http_code:     %{http_code}\n\
" https://example.com
```

**Đọc chỉ số:**
- `namelookup`: Thời gian phân giải DNS.
- `connect`: Thời gian hoàn thành TCP handshake.
- `tls_handshake`: Cao do TLS negotiation chậm hoặc server tải nặng.
- `ttfb`: (Time To First Byte) Cao thường do backend hoặc DB xử lý chậm.

---

## 5. TLS Certificate Debug

Chứng chỉ SSL/TLS bị lỗi? `curl` giúp kiểm tra nhanh chóng.

### Xem thông tin Certificate
```bash
curl -vI https://example.com 2>&1 | grep -A10 "Server certificate"
```

### Custom CA / Bỏ qua Verify
```bash
# Test nội bộ với CA tuỳ chỉnh
curl --cacert /path/to/ca.crt https://internal.example.com

# Bỏ qua verify (chỉ dùng debug, CẤM dùng trong production)
curl -k https://example.com
```

---

<!-- _class: divider -->

# 🔍 Phần 3
## Kịch bản thực chiến

---

## Kịch bản 1: "API trả 401/403"

```bash
# Decode JWT token bằng terminal để kiểm tra (không cần browser):
echo "${TOKEN}" | cut -d'.' -f2 | base64 -d | python3 -m json.tool
```
*Lưu ý: Check `exp` (expiry), scopes, hoặc issuer trong payload JWT trước khi tìm lỗi ở backend.*

## Kịch bản 2: "CDN có cache đúng không?"
```bash
# Kiểm tra cache headers
curl -sI https://example.com/static/app.js | grep -iE "cache-control|x-cache|age|etag"
# Trả về: X-Cache: HIT → CDN cache hit
# Trả về: X-Cache: MISS → Lấy dữ liệu từ origin
```

---

<!-- _class: divider -->

# 📊 Phần 4
## Bảng tra cứu Status Code

---

## Ý nghĩa HTTP Status Code khi Debug

| Code | Ý nghĩa trong Debug | Bước xử lý tiếp theo |
|:---|:---|:---|
| `000` | Không kết nối / Timeout | Dùng `nc -zv` kiểm tra IP/Port bị chặn |
| `301/302` | Bị redirect | Dùng `curl -v -L` để theo dõi chuỗi redirect |
| `400` | Client gửi sai định dạng | Check Header `Content-Type` & JSON body |
| `401` | Lỗi Auth / Expired Token | Check ngày giờ trên server, decode JWT |
| `403` | Thiếu quyền (Role/ACL) | Check WAF, IAM, Security Groups |
| `404` | Không tìm thấy route | Check router cấu hình Nginx/Ingress |
| `502` | Upstream down/crash | Check app backend (có đang chạy không) |
| `503` | Quá tải / Healthcheck fail | `ss -tlnp` check app còn listen port không |
| `504` | Upstream xử lý quá lâu | Xem `ttfb` với `curl -w` để check backend |

---

<!-- _class: title -->

# Cảm ơn đã theo dõi! 🙏

**Network Thực Chiến**

> *Tóm lại: Dùng `curl -v` xem chi tiết Header/TLS và `curl -w` để tìm bottleneck về hiệu năng. 2 lệnh đủ debug 90% các lỗi HTTP/HTTPS.*
