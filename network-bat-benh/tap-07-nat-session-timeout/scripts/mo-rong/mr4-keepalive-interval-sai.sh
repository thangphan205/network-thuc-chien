#!/usr/bin/env bash
# ==============================================================================
# MR4 — Keepalive CO bat, van chet: interval lon hon NAT timeout
#
# Ca bay pho bien nhat khi ap dung "thuoc" KB3 sai lieu luong: bat keepalive
# that, nhung dat interval (10s) LON HON established timeout cua NAT (5s).
# Probe dau tien ban ra thi da qua muon -- entry chet truoc khi kip lam moi.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

buoc "MR4 — NAT timeout=5s, keepalive CO bat nhung keepidle=10s (> 5s)"
dat_tcp_timeout 5
dat_loose 0
dat_nginx dai

echo "  Mo ket noi bang keepalive keepidle=10 (interval > NAT timeout), idle 7s, GET #2:"
N=$(docker exec $CLIENT sh -c "
  { printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: keep-alive\r\n\r\n';
    sleep 7;
    printf 'GET / HTTP/1.1\r\nHost: $IP_SERVER\r\nConnection: close\r\n\r\n';
    sleep 2; } | socat -t 15 - TCP:$IP_SERVER:80,keepalive,keepidle=10,keepintvl=10,keepcnt=3 | grep -c '^HTTP/1.1 200'
" 2>/dev/null | tr -d ' \r')
echo "  👉 So phan hoi HTTP 200 nhan duoc: ${N}/2"
echo ""
echo "👉 Doc chu ky:"
echo "   • keepalive DA BAT, ma van chi ${N}/2 — y het KB2 (khong keepalive)."
echo "   • Ly do: probe dau tien du kien ban o giay thu 10, nhung entry NAT da"
echo "     bi xoa o giay thu 5. Khong con goi nao den lam moi entry TRUOC KHI"
echo "     no het han -- 'bat keepalive' khong tu dong bang 'cau hinh dung'."
echo "   • Quy tac chon interval: keepidle PHAI NHO HON established timeout cua"
echo "     thiet bi NAT/firewall thuc te dang dung. Ngoai doi ban thuong KHONG"
echo "     biet con so do (350s cua AWS NAT Gateway la mot moc tham khao pho"
echo "     bien) — an toan nhat la dat keepidle 30-60s, gan nhu luon nho hon"
echo "     moi thiet bi NAT doanh nghiep/cloud dang ban."
