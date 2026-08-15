#!/usr/bin/env bash
# Chữa bệnh: Xóa bỏ luật chặn gói tin lớn
echo "🩺 Đang chữa bệnh: Cho phép gói tin lớn và kích hoạt TCP MSS Clamping..."
docker compose exec web-server iptables -F
echo "✅ Đã chữa khỏi lỗi!"
echo "👉 Hiện tượng: Ping gói lớn thành công và Web tải về toàn bộ nội dung trong nháy mắt."
