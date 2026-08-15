#!/usr/bin/env bash
# Script test nhanh từ máy Host (Laptop)
echo "=========================================="
echo "🩺 [BƯỚC 1] Bắt mạch L3: Kiểm tra Ping..."
echo "=========================================="
ping -c 3 127.0.0.1

echo ""
echo "=========================================="
echo "🩺 [BƯỚC 2] Bắt mạch L4/L7: Kiểm tra Web (cổng 8080)..."
echo "=========================================="
curl -Iv --connect-timeout 4 http://127.0.0.1:8080

echo ""
echo "=========================================="
