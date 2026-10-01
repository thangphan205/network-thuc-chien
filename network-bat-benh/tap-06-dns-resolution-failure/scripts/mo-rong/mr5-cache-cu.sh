#!/usr/bin/env bash
# ==============================================================================
# MR5 — BO DEM GIU IP CU.  ⭐ Chu ky: "sua roi ma van sai".
#
# Tinh huong ngoai doi: ban chuyen server, sua ban ghi A, dig kiem tra thay dung
# IP moi. Nhung ung dung tren may van vao dia chi cu. Ban restart ung dung —
# van the. Ban do cho "TTL chua het" roi ngoi cho... trong khi thu pham nam ngay
# tren chinh may do.
#
# Co che: nscd (hoac systemd-resolved, hoac chinh JVM) dem ket qua getaddrinfo().
# `dig` KHONG di qua nscd — no ban goi UDP thang toi nameserver. Vi vay dig thay
# du lieu MOI trong khi ung dung van an du lieu CU. Hai cong cu, hai su that.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

# ./scripts/mo-rong/mr5-cache-cu.sh --chua  -> chi chay phan chua roi thoat
if [ "${1:-}" = "--chua" ]; then
    echo "🩺 Xóa bộ đệm hosts của nscd..."
    docker exec $CLIENT nscd -i hosts >/dev/null 2>&1 || true
    sleep 1
    echo "   IP theo NSS/app bây giờ: $(ip_theo_nss)"
    echo "   IP theo dig            : $(ip_theo_dig)"
    echo "✅ Hai con số đã khớp. Bộ đệm được xóa NGAY, không phải ngồi đợi hết TTL."
    exit 0
fi

echo "🚨 MR5 — bật nscd (bộ đệm DNS của hệ thống) và nạp tên vào cache..."
docker exec $CLIENT sh -c "pkill -x nscd 2>/dev/null; rm -f /var/db/nscd/* 2>/dev/null; nscd" >/dev/null 2>&1 || true
sleep 1
docker exec $CLIENT sh -c 'pgrep -x nscd >/dev/null && echo "   nscd đang chạy, TTL hosts = 60 giây"'
# ⚠️ Phai ham nong cache bang CA HAI duong: `getent hosts` (tra cuu IPv4 thuan)
#    va mot lan `curl` that (getaddrinfo voi AF_UNSPEC). nscd dem hai loai truy
#    van nay o HAI KHOA KHAC NHAU — chi ham nong mot ben thi ben kia van di hoi
#    moi, va ca benh se tu mau thuan ngay tren man hinh.
docker exec $CLIENT getent hosts "$TEN" >/dev/null 2>&1 || true
docker exec $CLIENT sh -c "curl -s -o /dev/null --max-time 3 'http://$TEN/'" >/dev/null 2>&1 || true
echo "   Đã nạp vào cache: $TEN -> $(ip_theo_nss)"

echo ""
echo "🚨 Bây giờ đổi bản ghi trên DNS server sang $IP_WEB_CU (như vừa chuyển server)..."
xoa_log_dns
doi_ban_ghi "$TEN" "$IP_WEB_CU"
sleep 1

buoc "CHU KỲ: dig thấy IP MỚI, ứng dụng vẫn dùng IP CŨ"
in_chu_ky
echo ""
echo "👉 Đọc chu kỳ:"
echo "   • IP theo dig     = $IP_WEB_CU  (MỚI — DNS server đã cập nhật xong)"
echo "   • IP theo NSS/app = $IP_WEB  (CŨ — nscd vẫn đang giữ kết quả trước đó)"
echo "   • Hai dòng LỆCH NHAU, giống KB3. Nhưng ở KB3 /etc/hosts có dòng thừa,"
echo "     còn ở đây /etc/hosts SẠCH:"
docker exec $CLIENT sh -c "grep -c 'lab.local' /etc/hosts 2>/dev/null; true" | head -1 | sed 's/^/       số dòng lab.local trong \/etc\/hosts: /'
echo "     -> không phải hosts. Thủ phạm là BỘ ĐỆM."

echo ""
echo "  --- Bằng chứng: khởi động lại ứng dụng KHÔNG cứu được ---"
IFS='|' read -r _c RIP2 _r <<<"$(curl_thu)"
echo "     Chạy curl lần nữa, một tiến trình HOÀN TOÀN MỚI -> kết nối tới: ${RIP2:-(không tới đâu)}"
echo "     Vẫn IP cũ. Cache không nằm trong ứng dụng, nó nằm trong nscd —"
echo "     giết ứng dụng bao nhiêu lần cũng vô ích."

echo ""
echo "  --- CÁCH CHỮA (chưa chạy — để bạn tự chạy và tự quan sát) ---"
echo "     docker exec $CLIENT nscd -i hosts        # xóa bộ đệm hosts NGAY"
echo "     (hoặc chờ hết 60 giây TTL, hoặc: pkill nscd)"
echo ""
echo "     Chạy sẵn bằng:  ./scripts/mo-rong/mr5-cache-cu.sh --chua"
echo ""
echo "  --- NẾU CLIENT THẬT CỦA BẠN KHÔNG PHẢI DEBIAN NHƯ LAB NÀY ---"
echo "     Lab dùng nscd để minh họa. Ngoài đời, lớp đệm tùy hệ điều hành:"
echo ""
echo "     🐧 Ubuntu 24.04 (systemd-resolved, resolv.conf = 127.0.0.53):"
echo "        resolvectl query $TEN                  # IP ứng dụng thấy (qua bộ đệm)"
echo "        resolvectl statistics                    # xem 'Current Cache Size', 'Cache Hits'"
echo "        sudo resolvectl flush-caches             # XÓA bộ đệm NGAY"
echo "        resolvectl query $TEN                  # kiểm lại: phải ra IP mới"
echo "        dig @<IP DNS thật> $TEN               # đối chứng (IP thật: resolvectl status)"
echo "        (vẫn sai? sudo systemctl restart systemd-resolved)"
echo ""
echo "     🪟 Windows 10/11 (dịch vụ DNS Client — Dnscache), PowerShell chạy bằng Administrator:"
echo "        Resolve-DnsName $TEN                   # IP ứng dụng thấy (đọc cả hosts + cache)"
echo "        Get-DnsClientCache -Entry $TEN         # xem bản ghi đang bị giữ + TTL còn lại"
echo "        ipconfig /flushdns                       # XÓA bộ đệm NGAY"
echo "        (hoặc PowerShell: Clear-DnsClientCache)"
echo "        nslookup $TEN <IP DNS thật>            # đối chứng, như dig @<IP> (bỏ qua bộ đệm)"
echo "        Lưu ý: Windows không có getent — dùng Resolve-DnsName hoặc ping $TEN."
echo ""
echo "     ⚠️  Xóa bộ đệm hệ điều hành CHƯA đủ nếu ứng dụng tự đệm riêng:"
echo "        Chrome: chrome://net-internals/#dns -> Clear host cache; Java: khởi động lại JVM."
echo ""
echo "  ℹ️  Ca bệnh được GIỮ NGUYÊN để bạn chạy ./scripts/test.sh và thấy nó tự"
echo "     chẩn đoán ra MR5. Chạy ./scripts/0-setup.sh để reset."

echo ""
echo "🔑 Bài học:"
echo "   • 'dig ra đúng rồi mà vẫn lỗi' KHÔNG phải chuyện hoang đường. Nó có nghĩa"
echo "     là giữa ứng dụng và DNS server còn một lớp đệm mà dig không đi qua."
echo "   • Các lớp đệm hay gặp: nscd, systemd-resolved (127.0.0.53), dnsmasq trên"
echo "     máy, bộ đệm của chính runtime (JVM cache DNS VĨNH VIỄN nếu"
echo "     networkaddress.cache.ttl = -1), và bộ đệm của trình duyệt."
echo "   • Ubuntu 24.04+: lớp đệm mặc định là systemd-resolved (127.0.0.53)."
echo "     dig KHÔNG @ cũng đi qua nó -> dùng: dig @<IP DNS thật> $TEN"
echo "     Xóa bộ đệm: sudo resolvectl flush-caches   (Windows: ipconfig /flushdns)"
echo "   • Lệnh kiểm tra đúng vẫn là: getent hosts $TEN"
echo "     Nếu nó lệch với dig -> đi tìm lớp đệm, đừng đổ lỗi cho DNS server."
