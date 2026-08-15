#!/usr/bin/env bash
# Chữa bệnh: Khôi phục lại DNS Server chuẩn của Docker (127.0.0.11)
echo "🩺 Đang chữa bệnh: Khôi phục DNS nameserver về 127.0.0.11..."
docker compose exec client sh -c "echo 'nameserver 127.0.0.11' > /etc/resolv.conf && echo 'options ndots:0' >> /etc/resolv.conf"
echo "✅ Đã khôi phục DNS thành công!"
echo "👉 Hiện tượng: Client đã phân giải được tên miền 'web-server' và truy cập bình thường."
