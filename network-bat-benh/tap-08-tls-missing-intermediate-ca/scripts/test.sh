#!/usr/bin/env bash
# Script test kiểm tra chuỗi Certificate Chain
echo "=========================================="
echo "🩺 [BƯỚC 1] Soi chuỗi chứng chỉ bằng OpenSSL (Certificate Chain):"
echo "=========================================="
echo | openssl s_client -connect 127.0.0.1:8444 -servername app.chain.local -showcerts 2>&1 | grep -E "Certificate chain| s:| i:"

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Kiểm tra kết nối HTTPS với Root CA (Trust Store):"
echo "=========================================="
curl -Iv https://127.0.0.1:8444 --cacert nginx/ssl/rootCA.crt --resolve app.chain.local:8444:127.0.0.1 https://app.chain.local:8444 2>&1 | grep -E "SSL certificate problem|HTTP/1.1 200|SSL connection using"

echo ""
echo "=========================================="
