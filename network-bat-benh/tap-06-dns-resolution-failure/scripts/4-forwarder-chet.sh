#!/usr/bin/env bash
# ==============================================================================
# KB4 — DNS LOCAL SONG, DUONG RA UPSTREAM CHET.  Chu ky: dig "timed out" giong KB2.
#
# Ngoai doi day la ca "ping 8.8.8.8 duoc, dig ten ngoai chet, ten noi bo van 0 ms":
# DNS noi bo song, nhung forwarder/upstream (AD, DNS chi nhanh, ISP) khong tra loi.
# Lab dung vung `noi-bo.local` -> .99 de mo phong dung ket qua do.
#
# Tinh huong ngoai doi: DNS noi bo cua cong ty chuyen tiep vung `noi-bo.local`
# len mot may chu khac (AD, DNS chi nhanh). May do chet. Resolver van song, van
# tra loi moi vung khac, chi rieng vung duoc chuyen tiep la im lang.
#
# ⭐ GIA TRI CHAN DOAN CUA KICH BAN NAY:
#    `dig` cho ra CHINH XAC cung mot dong loi va cung mot khoang thoi gian nhu
#    KB2 (~2000 ms, "timed out"). Nhin vao man hinh dig, ban KHONG the phan biet
#    "khong toi duoc resolver" voi "resolver khong tra loi duoc". Chi co GOC NHIN
#    PHIA SERVER moi tra loi: log co dong query hay khong.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TEN_NB=db.noi-bo.local

echo "🚨 KB4 — cấu hình dnsmasq chuyển tiếp vùng noi-bo.local sang $IP_MA (máy đã chết)..."
docker exec $DNS sh -c "cp /etc/dnsmasq/dnsmasq.conf.default $CONF && printf 'server=/noi-bo.local/%s\n' '$IP_MA' >> $CONF"
nap_lai_dns
sleep 1
xoa_log_dns

buoc "CHU KỲ: dig 'timed out' — SAO Y KB2"
in_chu_ky "$TEN_NB"

echo ""
echo "  --- GÓC NHÌN PHÍA DNS SERVER (đây mới là chỗ tách bệnh) ---"
log_dns 6 | sed 's/^/  /'

echo ""
echo "👉 Đọc chu kỳ:"
echo "   • dig: 'communications error to $IP_DNS#53: timed out', bỏ cuộc sau ~2000 ms."
echo "     Đặt cạnh KB2 thì hai màn hình dig GIỐNG NHAU từng chữ (chỉ khác địa chỉ IP)."
echo "   • 'query tới server' > 0 — ĐÂY LÀ ĐIỂM TÁCH BỆNH. Gói tin ĐÃ TỚI NƠI."
echo "     Log server ghi rõ: nhận câu hỏi -> 'forwarded ... to $IP_MA' -> KHÔNG có dòng"
echo "     'reply' nào -> rồi tắc. Ở KB2 con số này là 0: câu hỏi chưa bao giờ tới server."
echo "     (Nếu log có CẢ 'query' lẫn 'reply' mà client vẫn timeout thì gói trả lời bị chặn"
echo "      trên đường VỀ — firewall/rp_filter — không phải KB4.)"
echo ""
echo "🔎 Chi tiết đáng chú ý — thời gian của curl khác KB2:"
echo "     KB2: curl trần ~3,8 s, exit 6   (cả 2 tên đều im lặng: 2 s + 2 s)"
echo "     KB4: curl trần ~2,0 s, exit 6   (tên thứ nhất im lặng 2 s, tên thứ hai ra ngay)"
echo "   Vì sao? Ứng dụng KHÔNG chỉ hỏi một tên. Với 'search lab.local' trong"
echo "   /etc/resolv.conf, glibc hỏi lần lượt:"
echo "       1. $TEN_NB           -> chuyển tiếp sang máy chết -> im lặng 2 s"
echo "       2. $TEN_NB.lab.local -> thuộc vùng lab.local -> NXDOMAIN NGAY"
echo "   Còn dig thì chỉ hỏi ĐÚNG cái tên bạn gõ, không nối thêm hậu tố nào."
echo "   Lưu ý: curl của lab có --connect-timeout 3 nên KB2 bị cắt ở exit 28 còn KB4"
echo "   kịp kết thúc ở exit 6. Đó là hệ quả của timeout trong script, KHÔNG phải"
echo "   chữ ký bền — đừng dùng exit code để tách KB2 và KB4."
echo ""
echo "🔑 Hai bài học:"
echo "   1. 'DNS timeout' ở client CHƯA nói lên điều gì. Phải hỏi tiếp: gói tin có"
echo "      tới được DNS server không? Hai nguyên nhân, hai cách chữa, một triệu chứng."
echo "   2. dig và ứng dụng đi HAI CON ĐƯỜNG KHÁC NHAU. dig hỏi đúng tên bạn gõ;"
echo "      ứng dụng còn thử thêm các hậu tố trong 'search'. Kết quả có thể khác nhau."
echo ""
echo "   Đối chứng — cùng lúc đó, vùng lab.local VẪN CHẠY BÌNH THƯỜNG:"
echo "     $TEN -> $(ip_theo_dig)"
echo "   Resolver KHÔNG chết. Chỉ một vùng bị câm. Nếu bạn kết luận 'DNS server chết'"
echo "   rồi đi khởi động lại nó, bạn đã chữa nhầm bệnh."
echo ""
echo "👉 Chẩn đoán: ./scripts/test.sh $TEN_NB"
echo "   (PHẢI truyền tên — test.sh mặc định hỏi $TEN, vùng lab.local vẫn khỏe)"
