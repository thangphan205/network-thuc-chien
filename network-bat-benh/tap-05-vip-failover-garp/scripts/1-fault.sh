#!/usr/bin/env bash
# Kích hoạt lỗi: MASTER chết, BACKUP cướp VIP nhưng KHÔNG phát Gratuitous ARP.
# Đây là kịch bản failover HA (Keepalived/VRRP/Pacemaker) đời thật khi script
# failover tự viết tay quên mất bước thông báo lại địa chỉ MAC cho toàn LAN.
set -e
VIP=172.28.5.100

echo "🚨 Đang kích hoạt lỗi: Failover không phát GARP..."

echo "   [1/2] node-a (MASTER) chết..."
docker compose stop node-a >/dev/null 2>&1

echo "   [2/2] node-b (BACKUP) cướp VIP $VIP — KHÔNG gửi GARP..."
docker compose exec node-b ip addr replace $VIP/24 dev eth0

echo "✅ Failover 'thành công': VIP đã nằm trên node-b, nginx vẫn chạy, cấu hình đúng 100%."
echo "👉 Hiện tượng: Client vẫn CHẾT — vì bảng ARP của nó còn ôm MAC của node-a đã tắt thở."
