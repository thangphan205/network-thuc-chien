#!/usr/bin/env bash
# Cảnh kết: KHÔNG chữa gì cả, chỉ ngồi chờ — đo xem bao lâu thì Linux tự khỏi.
# Chạy script này NGAY SAU 1-fault.sh (đừng chạy 2-fix.sh trước).
# Mục đích: đối chiếu "downtime khi quên GARP" với "0 giây khi có GARP".
#
# ⚠️ Đo bằng ĐỒNG HỒ THẬT (date +%s), không đếm vòng lặp: mỗi vòng tốn
#    ~1s chờ ping timeout + 1s sleep, đếm vòng sẽ ra số nhỏ hơn thực tế ~2 lần.
VIP=172.28.5.100

echo "⏱️  Không chữa gì cả. Chỉ ping mỗi giây và đếm xem bao giờ tự sống lại..."
docker compose exec client sh -c "
  START=\$(date +%s)
  while [ \$(( \$(date +%s) - START )) -lt 180 ]; do
    if ping -c 1 -W 1 $VIP >/dev/null 2>&1; then
      echo \"💡 TỰ KHỎI sau ~\$(( \$(date +%s) - START )) giây — không ai chạm vào gì cả.\"
      ip neigh show | grep $VIP
      exit 0
    fi
    sleep 1
  done
  echo '❌ Vẫn chết sau 180 giây.'
"
echo "👉 Đó chính là khoảng downtime bạn tặng không cho khách hàng mỗi lần failover khi quên GARP."
