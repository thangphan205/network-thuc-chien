#!/usr/bin/env bash
# Kích hoạt lỗi: Xóa Default Gateway trên máy Client
echo "🚨 Đang kích hoạt lỗi: Xóa Default Route (default via ...) trên Client..."
docker compose exec client ip route del default 2>/dev/null || true
echo "✅ Đã xóa Default Gateway trên Client!"
echo "👉 Hiện tượng: Client giao tiếp với các máy trong mạng LAN (172.28.12.10) bình thường, nhưng không thể ra ngoài Internet hoặc dải mạng khác (Network is unreachable)."
