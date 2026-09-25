#!/usr/bin/env bash
# ==============================================================================
# KB2 — RESOLVER KHONG TOI DUOC.  Chu ky: TIMEOUT.
#
# Tinh huong ngoai doi: IP cua DNS server bi go sai trong DHCP/cloud-init, hoac
# firewall chan UDP 53, hoac DNS server da bi go bo nhung cau hinh chua ai sua.
#
# Vi sao tro vao 172.28.6.99 (IP TRONG lab) chu khong phai mot IP ngoai Internet?
# Vi IP ngoai lab se di ra host roi ra ISP: ISP blackhole thi ra timeout, ISP tra
# ICMP unreachable thi ra loi khac han, may rut mang thi ra loi khac nua. Lab
# phai cho CUNG MOT ket qua tren moi may, ke ca khi khong co Internet.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB2 — tro /etc/resolv.conf sang $IP_MA (khong co may nao o dia chi do)..."
xoa_log_dns
dat_resolv "$IP_MA"

buoc "CHU KY: TIMEOUT"
in_chu_ky
echo ""
echo "👉 Doc chu ky:"
echo "   • dig mat ~2000 ms roi bo cuoc  -> khong ai TRA LOI. (timeout:1 attempts:2 = 2 lan cho 1s)"
echo "   • curl bao exit 28 'Resolving timed out' — CHU Y: khong phai exit 6."
echo "     Rat de nham voi 'server cham'. Nhung 3 giay do la mat o khau PHAN GIAI,"
echo "     TCP chua he duoc mo."
echo "   • query toi server = 0  -> goi tin CHUA TUNG toi duoc DNS server."
echo "     Day la diem tach KB2 khoi KB5 (xem 5-forwarder-chet.sh): KB5 co trieu"
echo "     chung y het, nhung ben server log CO dong query."
