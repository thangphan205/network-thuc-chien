# 🔒 openssl — Chẩn đoán SSL/TLS chuyên sâu

`openssl s_client` là công cụ chẩn đoán tầng TLS/SSL (Layer 6) mạnh mẽ nhất, thường được sử dụng khi `curl` chỉ báo các lỗi chung chung về chứng chỉ.

---

## 📖 Cheatsheet

### 1. Kết nối cơ bản
```bash
openssl s_client -connect example.com:443
```
*   Thiết lập kết nối TLS/SSL đến server.
*   In ra thông tin về bộ mã hóa, giao thức TLS và chứng chỉ đầu cuối (Leaf Certificate).

### 2. Kiểm tra chuỗi chứng chỉ (Certificate Chain)
```bash
openssl s_client -connect example.com:443 -showcerts
```
*   Ép server hiển thị toàn bộ chuỗi chứng chỉ.
*   Rất hữu ích để phát hiện lỗi Nginx/Apache cấu hình thiếu file `fullchain.pem` (chỉ khai báo chứng chỉ domain mà thiếu chứng chỉ trung gian).

### 3. Debug Virtual Host với SNI
```bash
openssl s_client -connect example.com:443 -servername example.com
```
*   Khi một IP phục vụ nhiều tên miền, bạn **phải** dùng `-servername` (Server Name Indication).
*   Nếu không có `-servername`, server có thể trả về chứng chỉ mặc định không đúng với domain bạn cần test.

### 4. Lưu và Đọc chi tiết chứng chỉ
```bash
# Lấy chứng chỉ và lưu ra file
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null | openssl x509 -outform PEM > cert.pem

# Đọc chi tiết chứng chỉ (Issuer, SANs, Expiry Date)
openssl x509 -in cert.pem -noout -text
```

---

## 🔍 Kịch bản thực chiến

### "Browser vào được bình thường nhưng Curl / Python Requests báo lỗi chứng chỉ"
*   **Nguyên nhân thường gặp:** Server thiếu Intermediate Certificate. Trình duyệt tự tải bù được nhưng các công cụ CLI thì không.
*   **Cách kiểm tra:** Chạy lệnh `openssl s_client -connect api.example.com:443 -showcerts`.
*   **Dấu hiệu lỗi:** Nếu output chỉ hiển thị `0 s:/CN=api.example.com` mà không có số `1` (Intermediate), chứng tỏ cấu hình server bị sai. Cần sửa lại Nginx để dùng `fullchain.pem`.

### "Kiểm tra xem chứng chỉ có hỗ trợ các domain phụ không"
*   **Cách kiểm tra:** Lấy nội dung chứng chỉ và đọc `openssl x509 -noout -text | grep -A2 "Subject Alternative Name"`.
*   **Kết quả:** Bạn sẽ thấy danh sách các tên miền hợp lệ (`DNS:example.com, DNS:www.example.com`).

---

> **Tóm lại:** Luôn nhớ kẹp `-showcerts` và `-servername` khi dùng `openssl s_client` để có kết quả chính xác nhất khi debug các lỗi liên quan đến SSL/TLS.
