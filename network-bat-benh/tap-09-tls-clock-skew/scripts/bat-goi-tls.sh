#!/usr/bin/env bash
# ==============================================================================
# BAT GOI TIN TLS trong container client roi ghi ra .pcap de mo bang Wireshark.
#
#   ./scripts/bat-goi-tls.sh [so_giay] [12|13]
#       so_giay : thoi luong bat (mac dinh 12)
#       12|13   : ep phien ban TLS. MAC DINH la 12 — doc ky phan duoi de hieu
#                 vi sao ep TLS 1.2 lai la lua chon dung cho muc dich HOC.
#
# Bat TRONG container chu khong bat tren card mang cua may that: goi tin cua lab
# khong bao gio ra khoi bridge, tren macOS/Windows ban khong soi duoc bang
# Wireshark cai san. Bat trong container thi chay giong nhau tren moi HDH.
#
# ==============================================================================
# ⚠️ DIEU QUAN TRONG NHAT VE WIRESHARK TRONG TAP NAY — DOC TRUOC KHI BAT
#
# Rat nhieu tai lieu (va ban cu cua chinh README nay) noi rang khi cert hong ban
# se thay goi:
#       Alert (Level: Fatal, Description: Bad Certificate)
#
# DIEU DO KHONG DUNG voi lab nay, va thuong cung khong dung ngoai doi. Ba ly do,
# ca ba deu da duoc DO trong chinh lab nay bang tcpdump:
#
#   1. TLS 1.3 MA HOA CA ALERT.
#      Tu TLS 1.3, moi ban tin sau ServerHello deu nam trong lop ma hoa. Tren day
#      alert mang content-type 23 (application_data). Wireshark hien "Encrypted
#      Alert" — KHONG doc duoc description. Muon doc duoc phai ep TLS 1.2.
#
#   2. CLIENT DUNG OpenSSL THUONG KHONG GUI ALERT NAO CA.
#      OpenSSL xac thuc cert SAU khi bat tay xong. Do trong lab (curl --tls-max 1.2,
#      cert het han): client gui ClientKeyExchange + CCS + Finished, server dap
#      CCS + Finished, roi client gui thang FIN. Khong he co ban tin Alert.
#      `openssl s_client` tran con "de" hon: no chi gui close_notify (warning).
#      Chinh trinh duyet (BoringSSL/NSS) moi gui certificate_expired(45) that su.
#
#   3. Ma alert dung la certificate_expired (45), KHONG phai bad_certificate (42).
#
# 👉 Vay Wireshark dung de lam gi trong tap nay? De doc CHINH CAI CERT tren day
#    (ban tin Certificate luon o dang RO, ke ca TLS 1.3 thi... khong — xem duoi).
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

GIAY=${1:-12}
TLSV=${2:-12}
FILE="tls-$(date +%H%M%S).pcap"

if [ "$TLSV" = "12" ]; then
    CURL_TLS="--tlsv1.2 --tls-max 1.2"
    GHI_CHU="TLS 1.2 (ép) — Certificate và Alert đều ở dạng RÕ, đọc được"
else
    CURL_TLS=""
    GHI_CHU="TLS 1.3 — từ bản tin thứ 2 trở đi đều BỊ MÃ HÓA"
fi

echo "🦈 Bắt gói tin cổng 443 trong $CLIENT trong $GIAY giây..."
echo "   Chế độ: $GHI_CHU"
docker exec -d $CLIENT sh -c "tcpdump -i eth0 -s0 -w /tmp/cap.pcap 'tcp port 443' 2>/dev/null"
sleep 1

echo "   Đang sinh lưu lượng: curl https://$TEN/"
docker exec $CLIENT sh -c \
    "curl -sS $CURL_TLS -o /dev/null --connect-timeout 3 --max-time 8 --cacert $CA https://$TEN/ 2>&1 | head -1" \
    | sed 's/^/     /' || true

sleep "$GIAY"
docker exec $CLIENT pkill -x tcpdump 2>/dev/null || true
sleep 1
docker cp "$CLIENT:/tmp/cap.pcap" "./$FILE" >/dev/null

echo ""
echo "✅ Đã lưu: $(pwd)/$FILE"
echo "   Số gói: $(docker exec $CLIENT sh -c 'tcpdump -r /tmp/cap.pcap 2>/dev/null | wc -l' | tr -d ' ')"
echo ""
echo "👉 Mở bằng Wireshark, display filter:  tls"
echo ""
if [ "$TLSV" = "12" ]; then
cat <<'HD'
   TLS 1.2 — đây là chế độ NÊN DÙNG ĐỂ HỌC:

   • tls.handshake.type == 11        -> bản tin Certificate. Bung ra, vào
       Certificate -> signedCertificate -> validity
     đọc được ĐÚNG hai trường notBefore / notAfter mà client đem ra so với
     đồng hồ của nó. Đây mới là thứ đáng xem trong tập này.

   • tls.record.content_type == 21   -> Alert (nếu có).
     Với curl/openssl bạn sẽ KHÔNG thấy gói nào khớp — vì chúng không gửi alert,
     chúng bắt tay xong rồi FIN. Đó là kết quả ĐÚNG, không phải bắt hỏng.
     Muốn thấy alert thật: dùng trình duyệt thay vì curl.

   • Nhìn kỹ trình tự: ClientHello -> ServerHello, Certificate -> ...
     Nếu handshake CHẠY XONG rồi client mới FIN, thì kết luận là: client đã
     nhận đủ cert, tự mình phán xét, và tự bỏ cuộc. Server không từ chối ai cả.
HD
else
cat <<'HD'
   TLS 1.3 — đây là thứ bạn gặp NGOÀI ĐỜI, và nó che gần hết mọi thứ:

   • Chỉ ClientHello và ServerHello còn ở dạng rõ.
   • Certificate nằm trong EncryptedExtensions -> Wireshark hiện
     "Application Data", KHÔNG đọc được nội dung cert.
   • Alert (nếu có) hiện là "Encrypted Alert" — không có description.

   👉 Bài học: khi gỡ bắt tay TLS 1.3 ngoài đời, Wireshark KHÔNG cho bạn biết
      cert có vấn đề gì. Phải lấy cert bằng một đường khác:
          openssl s_client -connect host:443 -servername TEN </dev/null \
            | openssl x509 -noout -dates -subject -ext subjectAltName
HD
fi
echo ""
echo "   (chạy lại với tham số thứ 2 = 13 để xem đối chứng TLS 1.3:"
echo "    ./scripts/bat-goi-tls.sh $GIAY 13)"
