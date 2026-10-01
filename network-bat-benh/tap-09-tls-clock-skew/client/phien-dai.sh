#!/bin/sh
# ==============================================================================
# GIU MOT PHIEN TLS MO XUYEN QUA THOI DIEM CERT HET HAN.
#
#   phien-dai.sh [giay_cho] [host] [ip]
#
# Dung cho MR4. Muc dich chung minh mot dieu rat phan truc giac:
#
#   Thoi han cua chung chi CHI duoc kiem tra MOT LAN, luc bat tay.
#   Phien da mo roi thi khong ai kiem tra lai. Cert het han luc 2h sang khong
#   lam dut cac ket noi dang mo — dich vu chi "chet dan" khi client MOI ket noi.
#
# Cach lam: mo s_client, GIU stdin bang mot FIFO (khong dong => phien khong dut),
# ngu qua thoi diem cert het han, roi moi gui HTTP request tren CHINH phien do.
#
# -verify_return_error la mau chot: no bat s_client THOAT NGAY neu cert khong
# hop le luc bat tay. Phien con song sau buoc 1 => cert luc do THAT SU con han,
# khong phai s_client de cho qua.
# ==============================================================================
GIAY=${1:-90}
HOST=${2:-secure.local}
IP=${3:-172.28.9.10}

rm -f /tmp/req /tmp/resp
mkfifo /tmp/req

openssl s_client -connect "$IP:443" -servername "$HOST" \
    -CAfile /etc/ssl/lab/ca.crt -verify_return_error -quiet \
    < /tmp/req > /tmp/resp 2>&1 &
SPID=$!

# Giu dau ghi cua FIFO mo => s_client khong thay EOF => phien khong bi dong.
exec 3> /tmp/req

sleep 3
if ! kill -0 "$SPID" 2>/dev/null; then
    echo "❌ Bắt tay TLS THẤT BẠI ngay từ đầu:"
    sed 's/^/   /' /tmp/resp
    exit 1
fi
echo "✅ [$(date '+%H:%M:%S')] Bắt tay TLS THÀNH CÔNG — cert lúc này CÒN HẠN."
echo "   (dùng -verify_return_error nên nếu cert xấu, s_client đã thoát ở trên)"

echo "⏳ Giữ nguyên phiên, chờ $GIAY giây cho cert hết hạn..."
sleep "$GIAY"

# ------------------------------------------------------------------------------
# ⚠️ Phai kiem tra phien con song TRUOC khi ghi vao FIFO.
#
# Neu s_client da thoat (thuong la vi nginx dong ket noi nhan roi — xem
# client_header_timeout trong nginx/conf/*.conf) thi FIFO khong con ai doc.
# Ghi vao do => SIGPIPE => script nay chet AM THAM giua chung: khong dong loi,
# khong ma thoat, kich ban goi no cu the ngoi doi mot ket qua khong bao gio toi.
# Kiem tra truoc thi bien mot loi cam thanh mot dong thong bao doc duoc.
# ------------------------------------------------------------------------------
if ! kill -0 "$SPID" 2>/dev/null; then
    echo "❌ Phiên đã bị ĐÓNG trước khi kịp gửi request."
    echo "   Gần như chắc chắn là nginx đóng kết nối nhàn rỗi."
    echo "   Kiểm tra client_header_timeout/keepalive_timeout trong nginx/conf/shortlived.conf"
    echo "   (phải lớn hơn $GIAY giây). Nhật ký s_client:"
    sed 's/^/   /' /tmp/resp
    exit 1
fi

echo "📨 [$(date '+%H:%M:%S')] Cert đã hết hạn. Gửi HTTP request trên PHIÊN CŨ..."
printf 'GET / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n' "$HOST" >&3
sleep 3
exec 3>&-
wait "$SPID" 2>/dev/null

echo "--- Phản hồi nhận được trên phiên cũ ---"
sed 's/^/   /' /tmp/resp
