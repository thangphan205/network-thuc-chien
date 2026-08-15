#!/usr/bin/env bash
# Script test kiểm tra TLS Handshake
echo "=========================================="
echo "🩺 [BƯỚC 1] Kiểm tra cổng 8443 (TCP Handshake):"
echo "=========================================="
nc -zvw2 127.0.0.1 8443 2>&1

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Kiểm tra bắt tay TLS bằng OpenSSL:"
echo "=========================================="
echo | openssl s_client -connect 127.0.0.1:8443 -servername secure.local 2>&1 | grep -E "Verify return code|SSL-Session|CN ="

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Truy cập HTTPS bằng curl:"
echo "=========================================="
curl -Iv https://127.0.0.1:8443 --cacert nginx/ssl/ca.crt --resolve secure.local:8443:127.0.0.1 https://secure.local:8443 2>&1 | head -n 25

echo ""
echo "=========================================="
