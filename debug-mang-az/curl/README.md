# 🌐 curl — HTTP Debug từ terminal

`curl` không chỉ để download file. Trong tay kỹ sư, nó là công cụ debug HTTP/HTTPS đầy đủ nhất: xem headers, test auth, trace redirect chain, phân tích TLS cert, đo timing từng phase kết nối.

---

## 📖 Cheatsheet

### 1. Xem headers response — Lệnh dùng nhiều nhất
```bash
curl -I https://example.com
# Chỉ lấy headers, không lấy body (dùng HEAD method)

curl -v https://example.com
# Verbose: thấy request headers, response headers, TLS handshake
# Lines: * = curl internal, > = request gửi đi, < = response nhận về
```

### 2. Theo dõi redirect chain
```bash
curl -L https://example.com
# -L: follow redirect tự động

curl -v -L https://example.com 2>&1 | grep -E "< HTTP|Location:|> GET"
# Thấy toàn bộ chuỗi redirect
```

### 3. Custom headers — Test API / bypass cache
```bash
curl -H "Authorization: Bearer token123" https://api.example.com/v1/users
curl -H "Content-Type: application/json" -H "X-Request-ID: debug-001" https://api.example.com
curl -H "Cache-Control: no-cache" https://example.com   # Bypass CDN cache
```

### 4. POST request với JSON body
```bash
curl -X POST https://api.example.com/v1/items \
  -H "Content-Type: application/json" \
  -d '{"name": "test", "value": 42}'
```

### 5. Timing breakdown — Tìm phase chậm
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

Output:
```
namelookup:    0.012s   ← DNS resolution
connect:       0.025s   ← TCP 3-way handshake
tls_handshake: 0.089s   ← TLS negotiation (cao → cert chain dài hoặc slow server)
ttfb:          0.142s   ← Time To First Byte (cao → backend xử lý chậm)
total:         0.198s   ← Tổng cộng
http_code:     200
```

### 6. TLS Certificate debug
```bash
# Xem thông tin cert
curl -vI https://example.com 2>&1 | grep -A10 "Server certificate"

# Test với cert cụ thể (self-signed)
curl --cacert /path/to/ca.crt https://internal.example.com

# Bỏ qua verify cert (CHỈ DÙNG DEBUG, KHÔNG DÙNG PRODUCTION)
curl -k https://example.com

# Xem toàn bộ cert chain
openssl s_client -connect example.com:443 -showcerts
```

### 7. Debug qua Proxy
```bash
curl -x http://proxy:8080 https://example.com
curl --proxy-user user:pass -x http://proxy:8080 https://example.com

# Bỏ qua proxy cho host cụ thể:
curl --noproxy "internal.example.com" https://internal.example.com
```

### 8. Upload file / Form data
```bash
# Multipart form (như HTML form)
curl -F "file=@/path/to/file.jpg" -F "description=test" https://api.example.com/upload

# URL-encoded form
curl -d "username=admin&password=secret" https://example.com/login
```

### 9. Lưu cookies và gửi lại (test session)
```bash
curl -c cookies.txt https://example.com/login -d "user=admin&pass=secret"
curl -b cookies.txt https://example.com/dashboard   # Dùng cookie vừa lưu
```

### 10. Parallel requests — Test concurrency
```bash
# Gửi 10 request song song với xargs
seq 10 | xargs -P 10 -I{} curl -s -o /dev/null -w "%{http_code}\n" https://example.com
```

---

## 🔍 Kịch bản thực chiến

### "API trả về lỗi 401/403, không biết token sai hay header sai"
```bash
# So sánh request thành công vs thất bại
curl -v -H "Authorization: Bearer ${TOKEN}" https://api.example.com/resource

# Decode JWT token (nếu là JWT):
echo "${TOKEN}" | cut -d'.' -f2 | base64 -d | python3 -m json.tool
# Xem exp (expiry), iss, scope trong payload
```

### "HTTPS hoạt động trong browser nhưng không hoạt động trong container"
```bash
# Browser có system cert store, container có thể không có
curl -v https://internal-service.example.com 2>&1 | grep "SSL certificate"

# Fix: mount CA cert vào container hoặc dùng --cacert
curl --cacert /etc/ssl/certs/ca-bundle.crt https://internal-service.example.com
```

### "CDN có cache đúng không?"
```bash
# Kiểm tra cache headers
curl -sI https://example.com/static/app.js | grep -iE "cache-control|x-cache|age|etag"
# X-Cache: HIT → CDN cache hit
# X-Cache: MISS → CDN miss, lấy từ origin
# Age: 3600 → Cache được tạo 3600s trước

# Force miss để xem response từ origin:
curl -H "Cache-Control: no-cache" -sI https://example.com/static/app.js
```

### "Debug Kubernetes Service từ bên ngoài"
```bash
# Test trực tiếp Pod IP (từ trong cluster)
kubectl exec -it debug-pod -- curl http://pod-ip:8080/health

# Test qua Service ClusterIP
kubectl exec -it debug-pod -- curl http://my-service.default.svc.cluster.local:8080/health

# Test Ingress với Host header giả
curl -H "Host: myapp.example.com" http://ingress-controller-ip/api/health
```

---

## 📊 HTTP Status Code — Ý nghĩa debug

| Code | Nguyên nhân thường gặp | Bước tiếp theo |
| :--- | :--- | :--- |
| `000` | Không kết nối được, timeout | `nc -zv host port` kiểm tra port |
| `301/302` | Redirect vòng lặp | `curl -v -L` xem redirect chain |
| `400` | Request malformed | Kiểm tra Content-Type, body format |
| `401` | Chưa auth hoặc token sai | Decode token, kiểm tra expiry |
| `403` | Đúng token nhưng thiếu quyền | Kiểm tra RBAC, ACL, IP whitelist |
| `404` | Sai path hoặc service chưa deploy | Kiểm tra route trong app |
| `502` | Upstream down hoặc crash | Kiểm tra app process, log app |
| `503` | Service overload hoặc health check fail | `ss -tlnp` xem port còn listen không |
| `504` | Upstream timeout | `mtr` kiểm tra latency, `curl -w` xem TTFB |

---

> **Tóm lại:** `curl -v` cho thấy toàn bộ TLS handshake và HTTP headers. `curl -w` với timing template phân tích được chính xác bottleneck ở phase nào (DNS, TCP, TLS, hay backend). Hai lệnh này đủ debug 90% vấn đề HTTP/HTTPS.
