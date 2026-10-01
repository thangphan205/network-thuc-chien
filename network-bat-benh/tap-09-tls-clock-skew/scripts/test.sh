#!/usr/bin/env bash
# ==============================================================================
# CHAN DOAN: di tu ngoai vao trong, xac dinh o benh nam o dau.
#
# Thu tu 6 buoc khong phai ngau nhien — no la dung quy trinh nen lam ngoai doi
# khi nhan duoc cau than "trinh duyet bao chung chi khong hop le".
# Moi buoc deu in KET QUA va noi ro ket qua do LOAI TRU duoc gia thuyet nao.
#
# Chay duoc o BAT KY trang thai nao cua lab (khoe hay dang co benh).
#   ./scripts/test.sh [ten_mien]
#
# ⚠️ Script nay TU DOC trang thai lab, khong gia dinh ban vua chay kich ban nao.
#    Buoc 5 (clock skew) chi chay khi cert dang serve la cert CON HAN — vi neu
#    cert da het han san thi ba lan thu voi ba dong ho deu that bai, va ket qua
#    do khong day duoc dieu gi ca.
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TEN_HOI=${1:-$TEN}

buoc "[BƯỚC 1] Tầng 3/4 còn sống không? — TCP tới cổng 443"
TCP=$(tcp_thu)
if [ "$TCP" = "MO" ]; then
    echo "  ✅ TCP 172.28.9.10:443 từ client: MỞ."
    echo "  👉 Đường truyền, route, firewall L3/L4 đều OK. Mọi lỗi từ đây trở đi"
    echo "     nằm ở TẦNG 5/6 (bắt tay TLS) — đừng đi soi dây, soi iptables."
else
    echo "  ❌ TCP 443: ĐÓNG. Chưa đến lượt TLS."
    echo "  👉 Dừng lại ở đây: nginx chết, hoặc lab chưa chạy. ./scripts/0-setup.sh"
    exit 1
fi
echo ""
echo "  Từ máy thật (cổng publish $PORT_HOST):"
if nc -z -w2 127.0.0.1 "$PORT_HOST" >/dev/null 2>&1; then
    echo "    ✅ 127.0.0.1:$PORT_HOST cũng MỞ."
else
    echo "    ⚠️ 127.0.0.1:$PORT_HOST không mở — kiểm tra publish port trong compose."
fi

buoc "[BƯỚC 2] ĐỒNG HỒ HAI ĐẦU đang báo gì? — câu hỏi PHẢI hỏi đầu tiên"
GC=$(gio_client); GS=$(gio_server); L=$(lech_giay); LD=$(lech_doc_duoc "$L")
echo "  Đồng hồ CLIENT : ${GC:-?} GMT+7"
echo "  Đồng hồ SERVER : ${GS:-?} GMT+7"
echo "  LỆCH           : $LD"
echo ""
ABS=$L; [ "$ABS" -lt 0 ] && ABS=$(( -ABS ))
if [ "$ABS" -lt 3600 ]; then
    echo "  ✅ Hai đồng hồ khớp nhau (lệch < 1 giờ)."
    echo "  👉 Nghĩa là: nếu lát nữa có báo 'hết hạn' thì đó là SỰ THẬT về cert,"
    echo "     không phải ảo giác do lệch giờ. Bạn được quyền tin notBefore/notAfter."
    DONG_HO_OK=1
else
    echo "  ❌ LỆCH GIỜ LỚN. Từ đây trở đi, MỌI kết luận về thời hạn cert đều"
    echo "     KHÔNG đáng tin — vì 'hết hạn' là một phép so sánh với đồng hồ này."
    echo "  👉 Chữa đồng hồ TRƯỚC, rồi hãy kết luận về cert."
    DONG_HO_OK=0
fi
echo ""
echo "  Nguồn giờ đối chiếu (NTP server của lab): $(ntp_ket_qua)"

buoc "[BƯỚC 3] Server ĐANG SERVE cert nào? — đọc TỪ DÂY, không đọc từ đĩa"
echo "  Cert đặt trong nginx.conf : $(cert_dang_dat).crt"
echo ""
echo "  Cert thực sự nhận được trên dây:"
cert_tren_day "$TEN_HOI" | sed 's/^/    /'
echo ""
echo "  👉 Đọc từ dây chứ không đọc file trên đĩa, vì câu hỏi thật sự là 'server"
echo "     ĐANG serve cái gì'. Hai thứ đó lệch nhau mỗi khi ai đó thay cert mà"
echo "     quên reload — một trong những nguyên nhân phổ biến nhất của"
echo "     'tôi gia hạn cert rồi mà vẫn báo hết hạn'."

buoc "[BƯỚC 4] HAI GÓC NHÌN — openssl vs curl"
V=$(verify_openssl "$TEN_HOI")
IFS='|' read -r CODE RC MSG <<<"$(curl_thu "$TEN_HOI")"
echo "  openssl s_client (mặc định) : $V"
echo "  curl (ứng dụng thật)        : http=$CODE exit=$RC"
echo "                                ${MSG:-(không có thông báo lỗi)}"
echo ""
if [[ "$V" == 0\ \(ok\)* ]] && [ "$RC" != "0" ]; then
    echo "  ❗ HAI CÔNG CỤ NÓI NGƯỢC NHAU."
    echo "  👉 Gần như chắc chắn là lỗi TÊN MIỀN: s_client mặc định KHÔNG kiểm tra"
    echo "     tên miền, curl thì có. Kiểm chứng:"
    echo "       openssl s_client ... -verify_hostname $TEN_HOI"
    echo "         ->  $(verify_openssl "$TEN_HOI" "-verify_hostname $TEN_HOI")"
    echo "     SAN của cert: $(san_cert "$TEN_HOI")   —  bạn đang hỏi: $TEN_HOI"
elif [[ "$V" == 0\ \(ok\)* ]]; then
    echo "  ✅ Cả hai góc nhìn cùng đồng ý: cert khỏe."
else
    echo "  👉 Cả hai cùng báo lỗi. Đọc mã verify ở bước 5 để biết lỗi GÌ."
fi

buoc "[BƯỚC 5] KẾT LUẬN — đối chiếu mã verify VỚI độ lệch giờ"
in_chu_ky "$TEN_HOI"

buoc "[BƯỚC 6] KIỂM CHỨNG: cùng server, cùng cert, ba đồng hồ khác nhau"
NB=$(han_cert notBefore); NA=$(han_cert notAfter)
if [[ "$V" == 0\ \(ok\)* ]]; then
    echo "  Cert hiện tại CÒN HẠN ($NB -> $NA), nên phép thử này có nghĩa."
    echo "  Đổi mỗi đồng hồ client, giữ nguyên mọi thứ khác:"
    echo ""
    for MOC in "2035-01-01 00:00:00|2035 (tương lai)      " \
               "2020-01-01 00:00:00|2020 (quá khứ)        " \
               "|đúng giờ              "; do
        GIO_GIA="${MOC%%|*}"
        printf '    %s -> ' "${MOC##*|}"
        IFS='|' read -r C R M <<<"$(curl_thu "$TEN_HOI")"
        if [ "$R" = "0" ]; then echo "HTTP $C"; else echo "${M:-exit $R}"; fi
    done
    GIO_GIA=""
    echo ""
    echo "  👉 Ba kết quả khác nhau trên CÙNG MỘT cert đang còn hạn. Thông báo"
    echo "     'certificate has expired' ở dòng đầu KHÔNG nói gì về cert cả —"
    echo "     nó nói về đồng hồ của máy gõ lệnh."
else
    echo "  ⏭️  BỎ QUA — cert đang serve không hợp lệ sẵn ($V)."
    echo "     Chạy phép thử này lúc này sẽ cho ba lần thất bại giống nhau và"
    echo "     không chứng minh được điều gì. Muốn thấy: ./scripts/0-setup.sh"
    echo "     rồi ./scripts/3-client-lech-gio.sh"
fi

echo ""
echo "=========================================="
echo "🧭 Reset lab: ./scripts/0-setup.sh"
echo "=========================================="
