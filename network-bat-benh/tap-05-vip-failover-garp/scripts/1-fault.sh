#!/usr/bin/env bash
# Kích hoạt lỗi: Tạo Stale/Fake ARP entry trên máy Client
echo "🚨 Đang kích hoạt lỗi: Stale ARP Cache trên Client (Gán sai MAC cho Server 172.28.5.10)..."
docker compose exec client ip neigh replace 172.28.5.10 lladdr 02:42:ac:1c:05:ee dev eth0 nud permanent
echo "✅ Đã gán MAC sai (02:42:ac:1c:05:ee) vào bảng ARP của Client!"
echo "👉 Hiện tượng: Client cùng dải mạng nhưng không thể ping hay truy cập được Server do gửi nhầm MAC đích."
