#!/usr/bin/env bash
# Chữa bệnh: Khôi phục định tuyến đối xứng (Symmetric Routing)
echo "🩺 Đang chữa bệnh: Đảm bảo luồng đi và luồng về đi qua cùng 1 Firewall..."
docker compose exec server iptables -F
echo "✅ Đã chữa khỏi lỗi!"
echo "👉 Hiện tượng: Gói SYN-ACK quay về đúng tuyến và kết nối TCP hoàn tất thành công."
