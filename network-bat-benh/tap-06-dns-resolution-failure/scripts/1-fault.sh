#!/usr/bin/env bash
# Kích hoạt lỗi: Cấu hình sai DNS Server trên Client
echo "🚨 Đang kích hoạt lỗi: Trỏ DNS Resolver sang IP không tồn tại (192.0.2.53)..."
docker compose exec client sh -c "echo 'nameserver 192.0.2.53' > /etc/resolv.conf && echo 'options timeout:1 attempts:1' >> /etc/resolv.conf"
echo "✅ Đã cấu hình sai DNS trên Client!"
echo "👉 Hiện tượng: Ping IP 172.28.6.10 chạy tốt, nhưng gõ 'curl http://web-server' hoặc 'dig web-server' thì báo lỗi không thể phân giải tên miền."
