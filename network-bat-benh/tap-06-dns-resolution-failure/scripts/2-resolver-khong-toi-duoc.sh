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

echo "🚨 KB2 — trỏ /etc/resolv.conf sang $IP_MA (không có máy nào ở địa chỉ đó)..."
xoa_log_dns
dat_resolv "$IP_MA"

buoc "CHU KỲ: TIMEOUT"
in_chu_ky
echo ""
echo "👉 Đọc chu kỳ:"
echo "   • dig mất ~2000 ms rồi bỏ cuộc  -> không ai TRẢ LỜI. (timeout:1 attempts:2 = 2 lần chờ 1s)"
echo "   • curl trong lab (--connect-timeout 3) báo exit 28 'Resolving timed out'."
echo "     Rất dễ nhầm với 'server chậm'. Nhưng 3 giây đó là mất ở khâu PHÂN GIẢI,"
echo "     TCP chưa hề được mở."
echo "     Curl trần (không đặt timeout) chờ ~3,8 s rồi báo exit 6 'Could not resolve host':"
echo "     glibc thử 2 tên (web.lab.local, rồi web.lab.local.lab.local), mỗi tên 2 s."
echo "     Exit 28 chỉ là hệ quả của timeout 3 s do script đặt -> KHÔNG dùng exit code"
echo "     để tách KB2 khỏi KB4."
echo "   • tcpdump trên client chỉ thấy ARP 'who-has $IP_MA' lặp lại, KHÔNG có gói DNS nào:"
echo "     IP nameserver cùng subnet mà không ai trả lời ARP thì gói UDP không bao giờ"
echo "     lên dây. (Firewall DROP thật thì khác: gói DNS lên dây rồi mất.)"
echo "   • query tới server = 0  -> gói tin CHƯA TỪNG tới được DNS server."
echo "     Đây là điểm tách KB2 khỏi KB4 (xem 4-forwarder-chet.sh): KB4 có triệu"
echo "     chứng y hệt, nhưng bên server log CÓ dòng query."
