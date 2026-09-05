#!/usr/bin/env bash
# ==============================================================================
# KỊCH BẢN 2 — SỰ THẬT BỊ GIẤU: GARP CỨU ĐƯỢC GÓI TIN, KHÔNG CỨU ĐƯỢC PHIÊN TCP
#
# Kịch bản 1 đo được downtime ~3 giây và rất dễ khiến người xem kết luận:
# "có Keepalived là failover mượt". SAI.
#
# 3 giây đó là thời gian để một gói ICMP/một request HTTP MỚI đi lọt trở lại.
# Còn những kết nối TCP ĐANG MỞ tại thời điểm failover thì CHẾT HẲN — vì:
#   - Kết nối TCP gắn chặt vào một máy cụ thể (seq/ack, cửa sổ, buffer).
#   - node-b là một máy KHÁC, HAProxy là một tiến trình KHÁC, không hề biết gì
#     về phiên đang chạy dở trên node-a.
#   - Không có đồng bộ trạng thái (conntrackd / session replication) giữa 2 node.
#
# Kịch bản này tải file 2MB từ CLIENT REMOTE (qua router), tốc độ bị nginx bóp
# còn 100k/s nên mất ~20 giây, rồi giết MASTER ở GIỮA CHỪNG để thấy kết nối đó
# đứt hẳn và KHÔNG BAO GIỜ nối lại.
# ==============================================================================
set -e
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "📋 VIP đang nằm trên: $(vip_owner)"
echo ""
echo "⬇️  Bắt đầu tải file 2MB qua VIP (nginx bóp còn 100k/s -> mất ~20 giây)..."
# Không dùng curl --limit-rate: giới hạn phía client chỉ làm curl đọc chậm khỏi
# buffer, còn server đã đẩy hết dữ liệu đi rồi -> giết MASTER cũng không đứt.
# Phải để nginx bóp băng thông (limit_rate) thì dữ liệu mới thực sự còn đang
# chảy qua node-a tại thời điểm nó chết.
docker exec -d $CLIENT_REMOTE sh -c "
  rm -f /tmp/dl.result /tmp/big.bin
  curl -s --max-time 60 -o /tmp/big.bin \
       -w 'http=%{http_code} tai_ve=%{size_download}/2097152 bytes thoi_gian=%{time_total}s' \
       http://$VIP/big.bin > /tmp/dl.result 2>&1
  echo \" curl_exit=\$?\" >> /tmp/dl.result
"

sleep 5
echo "   (đã tải được ~5 giây, kết nối TCP đang mở...)"
echo ""
echo "💥 SIGKILL node-a NGAY GIỮA CHỪNG kết nối đang tải..."
docker compose kill node-a >/dev/null 2>&1

echo "⏳ Chờ 45 giây: Keepalived chuyển VIP sang node-b, đồng thời xem file có tải xong không..."
sleep 45

echo ""
echo "=========================================="
echo "📊 KẾT QUẢ"
echo "=========================================="
echo "VIP giờ nằm trên: $(vip_owner)   (Keepalived đã làm đúng việc của nó)"
echo ""
echo "Kết nối TCP đang tải dở:"
docker exec $CLIENT_REMOTE sh -c 'cat /tmp/dl.result 2>/dev/null | sed "s/^/   /"'
echo "   (curl_exit=0 là tải xong; 18 = tải thiếu; 28 = treo tới hết giờ)"

echo ""
echo "Còn một request MỚI thì sao?"
docker exec $CLIENT_REMOTE curl -s --max-time 5 -i "http://$VIP/" \
    | grep -iE '^HTTP/|^x-lb-node' | sed 's/^/   /'

echo ""
echo "=========================================="
echo "🔑 ĐỌC KỸ CHỖ NÀY"
echo "=========================================="
echo "   - Request MỚI: 200 OK, phục vụ bởi node-b -> hạ tầng đã khôi phục."
echo "   - Kết nối ĐANG MỞ: đứt giữa chừng, tải thiếu, curl báo lỗi."
echo ""
echo "   GARP chỉ sửa được Tầng 2 (frame gửi tới đúng MAC). Nó KHÔNG thể"
echo "   chuyển một phiên TCP đang chạy sang máy khác — không giao thức nào làm được."
echo ""
echo "   Ngoài đời điều này nghĩa là: mỗi lần failover, TẤT CẢ session đang mở đều"
echo "   đứt — truy vấn database dở dang, WebSocket, upload file lớn, streaming."
echo "   Ứng dụng PHẢI biết tự kết nối lại (retry/reconnect), nếu không người dùng"
echo "   nhìn thấy lỗi bất kể cụm HA của bạn hoàn hảo tới đâu."
echo ""
echo "   Muốn giữ được cả phiên đang mở thì cần thêm tầng khác:"
echo "     - conntrackd  : đồng bộ bảng conntrack giữa 2 node (cho firewall/NAT)"
echo "     - session replication ở tầng ứng dụng (shared Redis, sticky + failover)"
echo "     - hoặc chấp nhận: thiết kế client có retry."
echo ""
echo "👉 Reset: ./scripts/0-setup.sh   — rồi sang kịch bản 3 (ca bệnh quên GARP)."
