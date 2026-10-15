#!/usr/bin/env bash
# ==============================================================================
# GOC NHIN PHIA DNS SERVER — mo o mot terminal rieng, de chay suot buoi hoc.
#
# Vi sao khong dung `docker compose logs -f dns`? Vi dnsmasq duoc khoi dong bang
# `docker exec` (xem dns/dns-start) nen no khong phai PID 1 cua container —
# `docker compose logs` khong bat duoc dong nao. Log nam trong file.
#
# Day la cong cu tach KB2 khoi KB4: cung mot trieu chung phia client, khac nhau
# o cho man hinh nay co dong query hay khong.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
echo "📖 Đang đọc $LOG_DNS trong container $DNS  (Ctrl-C để thoát)"
echo "   query[...] = client hỏi | forwarded = chuyển tiếp đi | is <IP> = đã trả lời"
echo "--------------------------------------------------------------------------"
docker exec $DNS tail -n 20 -f $LOG_DNS
