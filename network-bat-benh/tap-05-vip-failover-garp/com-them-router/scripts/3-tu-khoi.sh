#!/usr/bin/env bash
# Đo downtime khi KHÔNG chữa gì cả, trong trường hợp có router ở giữa.
# Chạy NGAY SAU 1-fault.sh (đừng chạy 2-fix.sh trước).
# Đo bằng ĐỒNG HỒ THẬT, không đếm vòng lặp.
cd "$(dirname "$0")/.."
source scripts/_lib.sh

echo "⏱️  Không chữa gì cả. Ping mỗi giây và đếm xem bao giờ tự sống lại..."
echo "    (Ở đây router chạy LINUX — có state machine NUD nên còn tự khỏi."
echo "     Router thương mại chỉ có timer aging, xem com-them.md mục 5.)"
docker compose exec client sh -c "
  START=\$(date +%s)
  while [ \$(( \$(date +%s) - START )) -lt 180 ]; do
    if ping -c 1 -W 1 $VIP >/dev/null 2>&1; then
      echo \"💡 TỰ KHỎI sau ~\$(( \$(date +%s) - START )) giây.\"
      exit 0
    fi
    sleep 1
  done
  echo '❌ Vẫn chết sau 180 giây.'
"
