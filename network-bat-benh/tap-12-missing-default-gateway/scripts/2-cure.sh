#!/usr/bin/env bash
# Chữa bệnh: Khôi phục Default Gateway (172.28.12.1)
echo "🩺 Đang chữa bệnh: Thêm lại Default Route (default via 172.28.12.1)..."
docker compose exec client ip route del default 2>/dev/null || true
docker compose exec client ip route add default via 172.28.12.1 dev eth0
echo "✅ Đã khôi phục Default Gateway thành công!"
echo "👉 Hiện tượng: Client đã có thể định tuyến ra ngoài Internet thành công."
