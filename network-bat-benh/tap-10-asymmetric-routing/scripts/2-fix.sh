#!/usr/bin/env bash
# Chữa bệnh: Khôi phục định tuyến đối xứng (Symmetric Routing)
echo "🩺 Đang khắc phục sự cố (Fixing): Đảm bảo luồng đi và luồng về đi qua cùng 1 Firewall..."
docker compose exec server iptables -F
echo "✅ Đã khắc phục lỗi thành công!"
echo "👉 Hiện tượng: Gói SYN-ACK quay về đúng tuyến và kết nối TCP hoàn tất thành công."
