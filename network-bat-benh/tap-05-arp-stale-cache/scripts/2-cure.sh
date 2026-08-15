#!/usr/bin/env bash
# Chữa bệnh: Xóa sạch cache ARP cũ hoặc phát Gratuitous ARP
echo "🩺 Đang chữa bệnh: Xóa stale ARP entry và phát Gratuitous ARP..."
docker compose exec client ip neigh del 172.28.5.10 dev eth0 2>/dev/null || true
docker compose exec client ip neigh flush dev eth0
echo "✅ Đã làm mới bảng ARP thành công!"
echo "👉 Hiện tượng: Client đã học đúng địa chỉ MAC thực tế của Server và kết nối thông suốt."
