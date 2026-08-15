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
echo | openssl s_client -connect 127.0.0.1:8443 -servername secure.local -CAfile nginx/ssl/ca.crt 2>&1 | grep -E "Verify return code|SSL-Session|CN ="

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 3] Truy cập HTTPS bằng curl:"
echo "=========================================="
curl -Iv --cacert nginx/ssl/ca.crt --resolve secure.local:8443:127.0.0.1 https://secure.local:8443 2>&1 | head -n 25

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 4] Clock Skew thật sự: Client bị lệch đồng hồ (cert server VẪN hợp lệ):"
echo "=========================================="
echo "--- Đồng hồ Client chạy sang năm 2035 (tương lai) ---"
docker compose exec client sh -c "faketime '2035-01-01 00:00:00' curl -sS --cacert /etc/ssl/lab/ca.crt --resolve secure.local:443:172.28.7.10 https://secure.local/ 2>&1 | head -n 2"
echo "--- Đồng hồ Client tụt về năm 2020 (quá khứ - hết pin CMOS) ---"
docker compose exec client sh -c "faketime '2020-01-01 00:00:00' curl -sS --cacert /etc/ssl/lab/ca.crt --resolve secure.local:443:172.28.7.10 https://secure.local/ 2>&1 | head -n 2"
echo "--- Đồng hồ Client đúng giờ (đã đồng bộ NTP) ---"
docker compose exec client sh -c "curl -sS --cacert /etc/ssl/lab/ca.crt --resolve secure.local:443:172.28.7.10 https://secure.local/ 2>&1 | head -n 2"
