#!/usr/bin/env bash
# Test so sánh Ping gói nhỏ vs Ping gói lớn (DF set) và Tải Web qua Router

# Xoá PMTU cache (route exception) trên Client và Server.
# Vì sao cần: TEST 2 bắn ping 1450B kèm cờ DF -> Router trả về ICMP Type 3 Code 4,
# Client ghi luôn "mtu 1400" vào route cache. Nếu không xoá, TEST 3 sẽ mở kết nối
# TCP với MSS=1360 ngay từ gói SYN -> không gói nào vượt 1400 -> Router không phải
# sinh ICMP nào cả, và ta mất trắng phần PMTUD phía Server (phần hay nhất của lab).
reset_pmtu() {
  docker compose exec client ip route del 172.28.42.0/24 >/dev/null 2>&1 || true
  docker compose exec client ip route add 172.28.42.0/24 via 172.28.41.254
  docker compose exec web-server ip route del 172.28.41.0/24 >/dev/null 2>&1 || true
  docker compose exec web-server ip route add 172.28.41.0/24 via 172.28.42.254
}

echo "=========================================="
echo "🩺 [TEST 1] Ping gói nhỏ tiêu chuẩn (64 bytes) từ Client -> Server:"
echo "=========================================="
docker compose exec client ping -c 3 172.28.42.10

echo ""
echo "=========================================="
echo "🩺 [TEST 2] Ping gói lớn kèm cờ Don't Fragment (1450 bytes):"
echo "=========================================="
docker compose exec client ping -c 2 -s 1450 -M do 172.28.42.10 || true

echo ""
echo "=========================================="
echo "🧹 [RESET] Xoá PMTU cache trên Client & Server trước khi tải web"
echo "=========================================="
echo "👉 Trạng thái cache TRƯỚC khi xoá (chú ý dòng 'mtu 1400'):"
docker compose exec client ip route get 172.28.42.10
reset_pmtu
echo "👉 Trạng thái cache SAU khi xoá (đã sạch, không còn mtu):"
docker compose exec client ip route get 172.28.42.10

echo ""
echo "=========================================="
echo "🩺 [TEST 3] Tải trang Web từ Web Server (curl qua Router):"
echo "=========================================="
docker compose exec client curl -sS -o /dev/null -w "HTTP %{http_code} | tải về %{size_download} bytes | %{time_total}s\n" --connect-timeout 3 --max-time 6 http://172.28.42.10 \
  || echo "❌ curl treo/timeout — body không về được do MTU Blackhole!"
