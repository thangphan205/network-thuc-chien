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

# 🔒 openssl
## Chuẩn đoán SSL/TLS chuyên sâu từ Terminal

**Network Thực Chiến** · Series: Debug Mạng từ A–Z · Tập 07

---

## 📋 Nội dung

1. **Khái niệm cơ bản** — Tại sao cần `openssl s_client`?
2. **Kỹ thuật cốt lõi** — Xem Certificate & Certificate Chain.
3. **Mẹo thực chiến** — Xử lý SNI (Virtual Hosts).
4. **Giải mã chứng chỉ** — Đọc chi tiết bằng `openssl x509`.

> Khi `curl` chỉ báo lỗi "unable to get local issuer certificate", `openssl` chính là công cụ giúp bạn "mổ xẻ" nguyên nhân thực sự!

---

<!-- _class: divider -->

# 🚀 Phần 1
## Giới thiệu s_client

---

## 1. s_client là gì?

Nếu `nc` (Netcat) dùng để kết nối TCP/UDP thô (Layer 4), thì `openssl s_client` là công cụ tương đương cho tầng TLS/SSL (Layer 6).

### Kết nối cơ bản
```bash
openssl s_client -connect example.com:443
```
*   Thiết lập một kết nối TLS handshake đầy đủ.
*   In ra thông tin về bộ mã hóa (Cipher Suite), phiên bản TLS đang dùng.
*   Hiển thị **chứng chỉ đầu cuối (Leaf Certificate)** của server.

---

<!-- _class: divider -->

# 🔍 Phần 2
## Debug Certificate Chain

---

## 2. Nỗi đau "Thiếu Intermediate Certificate"

Lỗi kinh điển: Truy cập bằng trình duyệt thì "Xanh", nhưng gọi API bằng code (Python, Java) thì lỗi SSL. Nguyên nhân thường do Nginx cấu hình thiếu file `fullchain.pem`.

### Giải pháp: Ép server khai báo toàn bộ chuỗi chứng chỉ
```bash
openssl s_client -connect example.com:443 -showcerts
```
**Cách đọc kết quả:**
*   `0 s:/CN=example.com` → (Leaf) Chứng chỉ của domain.
*   `1 s:/CN=Intermediate CA...` → (Intermediate) Chứng chỉ trung gian.
*   *Nếu chỉ có số `0` mà không có số `1`? Server cấu hình thiếu chuỗi!*

---

<!-- _class: divider -->

# 💡 Phần 3
## Mẹo thực chiến (SNI)

---

## 3. Lỗi "Cùng 1 IP, nhiều Domain"

Khi một server chạy nhiều tên miền (Virtual Hosts), nếu bạn gọi IP hoặc port trực tiếp, server có thể trả về **sai chứng chỉ** (thường là chứng chỉ mặc định của Nginx).

### Bắt buộc sử dụng Server Name Indication (SNI)
```bash
openssl s_client -connect 10.0.0.5:443 -servername api.example.com
```
*   `-servername`: Báo cho server biết chính xác bạn muốn bắt tay TLS với tên miền nào trước khi chứng chỉ được gửi xuống.
*   *Luôn luôn dùng cờ này khi debug để đảm bảo kết quả chính xác nhất!*

---

<!-- _class: divider -->

# 📖 Phần 4
## Giải mã nội dung chứng chỉ

---

## 4. Dịch khối PEM sang Text

Đôi khi bạn có một khối mã PEM (hoặc copy từ kết quả `s_client`) và muốn biết bên trong ghi gì.

### Lưu khối chứng chỉ ra file `cert.pem`:
```text
-----BEGIN CERTIFICATE-----
MIIFI...
-----END CERTIFICATE-----
```

### Đọc chi tiết bằng con người:
```bash
openssl x509 -in cert.pem -noout -text
```
*   Xem được `Issuer` (Người cấp), `Validity` (Ngày hết hạn).
*   Xem `Subject Alternative Name` (SANs - Các tên miền phụ được hỗ trợ).

---

<!-- _class: title -->

# Cảm ơn đã theo dõi! 🙏

**Network Thực Chiến**

> *Tóm lại: Dùng `openssl s_client -showcerts -servername` để "nội soi" Certificate Chain khi server API bị lỗi SSL với các Client nghiêm ngặt.*
