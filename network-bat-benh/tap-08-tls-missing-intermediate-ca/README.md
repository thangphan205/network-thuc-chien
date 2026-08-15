# 🩺 Ca Bệnh 08: Thiếu Intermediate CA — PC Vào Được, Mobile/Curl Báo Lỗi SSL

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Kỹ sư mở trình duyệt Chrome trên máy tính (PC) truy cập website HTTPS thì thấy biểu tượng ổ khóa xanh bình thường. Nhưng khi người dùng mở bằng điện thoại (iOS/Android), ứng dụng Mobile App hoặc gọi API bằng `curl` / `Python requests` thì bị lỗi đứt gánh: **`unable to get local issuer certificate`** hoặc **`SSL Handshake Failed`**.
> * **Bản chất lỗi:** **Incomplete Certificate Chain ở Tầng 5/6 (TLS)**. Web server cấu hình chỉ gửi Server Certificate (Leaf Cert) mà quên không gửi kèm chứng chỉ trung gian (Intermediate CA Certificate) để nối liền chuỗi tin cậy (Trust Chain) về Root CA.

---

## 🔬 Sơ đồ Cây Tin Cậy TLS (Trust Chain)

```
[Root CA] (Đã cài sẵn trong hệ điều hành / Trust Store)
    │
    ▼ (Ký cấp)
[Intermediate CA]  <─── NGUYÊN NHÂN LỖI: Server quên không gửi cert này!
    │
    ▼ (Ký cấp)
[Server Certificate] (Chỉ có cert này trên Server)

-----------------------------------------------------------------------------
• Chrome trên PC: Tự động tải Intermediate Cert bị thiếu qua AIA (Authority Information Access) hoặc lấy từ bộ nhớ đệm Cache -> Vào được!
• Mobile App / curl / Backend Service: Không có AIA Fetching -> Đứt chuỗi tin cậy -> Báo lỗi SSL!
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-08-tls-missing-intermediate-ca
docker compose up -d --build
```

> **Lưu ý:** Chuỗi chứng chỉ 3 cấp (`Root CA -> Intermediate CA -> Server`) được service `certgen` **sinh tự động** mỗi lần `docker compose up`, nên lab không bao giờ bị lỗi cert hết hạn dù bạn chạy vào năm nào.

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi (chỉ load `server_only.crt`):
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy kiểm tra:
   ```bash
   ./scripts/test.sh
   ```

#### 🔍 Hiện tượng quan sát được:
1. **Kiểm tra Certificate Chain bằng OpenSSL:**
   ```
   Certificate chain
    0 s:CN = app.chain.local
      i:CN = 9Ping Intermediate CA
   ```
   👉 Chỉ có duy nhất 1 chứng chỉ tầng 0! Phía client không biết `9Ping Intermediate CA` là ai vì thiếu mắt xích trung gian.
2. **Curl báo lỗi:** `SSL certificate problem: unable to get local issuer certificate`.

---

### Bước 3: Khắc Phục Sự Cố (Fix & Remediate)

Chuyển cấu hình Nginx sang sử dụng file gộp **`fullchain.crt`** (`cat server.crt intermediate.crt > fullchain.crt`):
```bash
./scripts/2-fix.sh
```

Kiểm tra lại:
```bash
./scripts/test.sh
```

#### 🔍 Kết quả sau khi chữa:
```
Certificate chain
 0 s:CN = app.chain.local
   i:CN = 9Ping Intermediate CA
 1 s:CN = 9Ping Intermediate CA
   i:CN = 9Ping Root CA
```
👉 Chuỗi đầy đủ 2 tầng chứng chỉ đã được gửi kèm. Curl và Mobile App kết nối thành công `HTTP/1.1 200 OK`!

---

## 🧠 Bác Sĩ Mạng Đúc Kết: Quy Tắc Cấu Hình SSL Nginx / Apache Chuẩn

1. **Với Nginx:** Luôn trỏ `ssl_certificate` tới file `fullchain.pem` (Let's Encrypt) hoặc file gộp `bundle.crt` (Server Cert + Intermediate CAs). Tuyệt đối **không** trỏ tới file `cert.pem` đơn lẻ.
2. **Công cụ kiểm tra nhanh trên Internet:** Sử dụng công cụ miễn phí **SSLLabs SSL Test** (`ssllabs.com/ssltest/`) — nếu thấy cảnh báo màu cam *"Chain issues: Incomplete"* thì chính là lỗi này!

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
