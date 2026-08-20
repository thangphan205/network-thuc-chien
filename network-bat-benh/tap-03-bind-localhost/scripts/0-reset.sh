#!/usr/bin/env bash
# Đưa lab về trạng thái KHỎE MẠNH ban đầu (listen 0.0.0.0:80).
#
# Vì sao cần script này thay vì `docker compose up -d`?
#   `up -d` chạy lại config-init (ghi good.conf vào nginx/nginx.conf), nhưng thấy
#   web-server không đổi nên KHÔNG recreate container. Nginx giữ nguyên socket cũ
#   127.0.0.1:80 trong khi file trên đĩa đã ghi `listen 80;` -> file và socket lệch nhau,
#   học viên đọc config để chẩn đoán sẽ ra kết luận sai.
set -e
cd "$(dirname "$0")/.."
echo "♻️  Đang reset lab về trạng thái khỏe mạnh (listen 0.0.0.0:80)..."
cp nginx/conf/good.conf nginx/nginx.conf
docker compose restart web-server >/dev/null
echo "✅ Lab đã sẵn sàng. Kiểm tra: docker compose exec web-server ss -tulpn | grep :80"
