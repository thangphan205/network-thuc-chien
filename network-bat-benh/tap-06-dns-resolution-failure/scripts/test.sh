#!/usr/bin/env bash
# ==============================================================================
# CHAN DOAN: di tu ngoai vao trong, xac dinh o benh nam o dau.
#
# Thu tu 7 buoc khong phai ngau nhien — no la dung quy trinh ban nen lam ngoai
# doi khi nhan duoc cau than "ping IP thi duoc ma go ten mien thi chet".
# Moi buoc deu in KET QUA va noi ro ket qua do LOAI TRU duoc gia thuyet nao.
#
# Chay duoc o BAT KY trang thai nao cua lab (khoe hay dang co benh).
#   ./scripts/test.sh [ten_mien]
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TEN_HOI=${1:-$TEN}

buoc "[BƯỚC 1] Tầng 3 còn sống không? — ping THẲNG IP, không qua tên miền"
if docker exec $CLIENT ping -c2 -W1 $IP_WEB >/dev/null 2>&1; then
    echo "  ✅ ping $IP_WEB: THÔNG."
    echo "  👉 Đường truyền, route, firewall ở L3 đều OK. Mọi lỗi từ đây trở đi"
    echo "     KHÔNG phải lỗi mạng — đừng đi soi dây, soi switch, soi iptables."
    L3=1
else
    echo "  ❌ ping $IP_WEB: KHÔNG THÔNG."
    echo "  👉 Dừng lại ở đây. Chưa đến lượt DNS — đi sửa L2/L3 trước."
    L3=0
fi

buoc "[BƯỚC 2] Client đang hỏi AI? — /etc/resolv.conf"
docker exec $CLIENT cat /etc/resolv.conf 2>/dev/null | sed 's/^/  /'
NS=$(docker exec $CLIENT sh -c "awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf" 2>/dev/null | tr -d '\r')
echo ""
if [ "$NS" = "$IP_DNS" ]; then
    echo "  ✅ nameserver = $IP_DNS — đúng DNS server của lab."
else
    echo "  ❌ nameserver = ${NS:-(không có)} — KHÔNG phải $IP_DNS của lab."
    echo "  👉 Manh mối mạnh nhất. Đọc tiếp để xem nó im lặng hay từ chối."
fi

buoc "[BƯỚC 3] ỨNG DỤNG thật sự dùng IP nào? — getent hosts"
NSS=$(ip_theo_nss "$TEN_HOI")
echo "  getent hosts $TEN_HOI  ->  ${NSS:-(không ra gì)}"
echo "  👉 Đây là đường mà ứng dụng THẬT SỰ đi: /etc/hosts -> nscd -> DNS."
echo "     Không phải đường mà dig đi. Kiểm tra bằng getent, không phải bằng dig."
echo "  ℹ️  Ubuntu 24.04+ (resolv.conf = 127.0.0.53): dig không @ đi QUA bộ đệm"
echo "     systemd-resolved. Hỏi thẳng: dig @<IP trong 'resolvectl status'> <tên>."

buoc "[BƯỚC 4] DNS SERVER nói gì? — dig (bỏ qua hosts và nscd)"
RAW=$(dig_full "$TEN_HOI")
ST=$(dig_status_tu "$RAW"); QT=$(dig_qtime_tu "$RAW")
WALL=$(dig_wall_tu "$RAW"); DIP=$(dig_ip_tu "$RAW")
echo "  status     : $ST"
if [ "$ST" = "KHONG-TRA-LOI" ]; then
    echo "  lỗi        : $(dig_loi_tu "$RAW")"
    echo "  bỏ cuộc sau: ${WALL} ms"
    case "$(dig_loi_tu "$RAW")" in
        *"connection refused"*)
            echo "  👉 CÓ ai đó trả lời ngay: kernel máy DNS báo cổng 53 ĐANG ĐÓNG."
            echo "     Máy sống, DỊCH VỤ chết. -> MR1." ;;
        *"timed out"*)
            echo "  👉 KHÔNG ai trả lời trong ${WALL} ms. Hai khả năng, chưa phân biệt được:"
            echo "     gói tin chưa tới nơi (KB2)  HOẶC  tới nơi mà server không đáp (MR3)."
            echo "     BƯỚC 6 sẽ trả lời." ;;
        *)  echo "  👉 Lỗi bất thường — đọc kỹ dòng trên." ;;
    esac
else
    echo "  Query time : ${QT} ms"
    echo "  IP trả về  : ${DIP:-(không có bản ghi A)}"
    if [ "$ST" = "NXDOMAIN" ]; then
        echo "  👉 Server SỐNG và ĐÃ trả lời — câu trả lời là 'tên này không tồn tại'."
        echo "     ${QT} ms = nhanh = có người đáp. Đối lập hoàn toàn với timeout."
        echo "     Đây KHÔNG phải sự cố mạng. Gõ sai tên, hoặc thiếu bản ghi. -> MR2."
    fi
fi

buoc "[BƯỚC 5] SO SÁNH bước 3 với bước 4 — bước quan trọng nhất"
echo "  Ứng dụng dùng (NSS): ${NSS:-(không ra)}"
echo "  DNS server trả về  : ${DIP:-(không ra)}"
echo ""
if [ -n "$NSS" ] && [ -n "$DIP" ] && [ "$NSS" != "$DIP" ]; then
    echo "  ❌ LỆCH NHAU. Thủ phạm nằm TRÊN MÁY CLIENT, không phải trên DNS server."
    HOSTS=$(docker exec $CLIENT sh -c "grep -c '$TEN_HOI\$' /etc/hosts 2>/dev/null; true" | head -1 | tr -d '\r')
    if [ "${HOSTS:-0}" != "0" ]; then
        echo "     -> /etc/hosts có dòng đè lên tên này:"
        docker exec $CLIENT grep "$TEN_HOI\$" /etc/hosts 2>/dev/null | sed 's/^/        /'
        echo "     -> KB3. Chữa: xóa dòng đó."
    elif docker exec $CLIENT pgrep -x nscd >/dev/null 2>&1; then
        echo "     -> /etc/hosts sạch, nhưng nscd ĐANG CHẠY và giữ kết quả cũ."
        echo "     -> MR5. Chữa: nscd -i hosts (đừng ngồi đợi TTL)."
    else
        echo "     -> Không thấy hosts lẫn nscd. Tìm tiếp các lớp đệm khác"
        echo "        (systemd-resolved, cache của runtime)."
        echo "        Ubuntu 24.04+: sudo resolvectl flush-caches"
    fi
elif [ -n "$DIP" ]; then
    echo "  ✅ KHỚP NHAU. Không ai chen ngang giữa DNS và ứng dụng."
    if [ "$DIP" != "$IP_WEB" ]; then
        echo "  ❌ NHƯNG đây KHÔNG phải địa chỉ đúng của dịch vụ ($IP_WEB)."
        echo "     DNS trả lời trơn tru — và trả về SAI ĐỊA CHỈ. -> MR4."
        echo "     Chữa: sửa bản ghi A trên DNS server."
    fi
fi

buoc "[BƯỚC 6] Gói tin CÓ TỚI ĐƯỢC DNS server không? — log phía server"
Q=$(dem_query_o_server)
LOI=$(dig_loi_tu "$RAW")
echo "  Số dòng query[...] trong $LOG_DNS: $Q"
echo ""
# Ket luan o buoc nay CHI co nghia khi buoc 4 that bai. Neu dig da tra loi binh
# thuong thi so query > 0 la chuyen duong nhien, khong to cao ai ca.
if [ "$ST" != "KHONG-TRA-LOI" ]; then
    echo "  👉 Bước 4 đã có câu trả lời, nên con số này chỉ xác nhận server đang làm việc."
    echo "     Bước 6 chỉ dùng để PHÁ ÁN khi bước 4 báo 'timed out'."
elif [ "${Q:-0}" = "0" ]; then
    case "$LOI" in
        *"connection refused"*)
            echo "  👉 SỐ KHÔNG query — đúng như mong đợi: tiến trình DNS đã chết nên"
            echo "     không ai ghi log được. Kết luận vẫn là MR1 (bước 4 đã chỉ rõ)." ;;
        *)  echo "  👉 SỐ KHÔNG. Câu hỏi CHƯA TỪNG tới được server."
            echo "     Sai địa chỉ nameserver, hoặc firewall chặn UDP 53. -> KB2." ;;
    esac
else
    echo "  👉 CÓ query — gói tin ĐÃ TỚI NƠI, server nhận được câu hỏi."
    echo "     Mà bước 4 vẫn báo 'timed out' => lỗi nằm BÊN TRONG server"
    echo "     (forwarder chết, vùng bị câm). -> MR3, KHÔNG phải KB2."
    echo ""
    echo "  4 dòng log cuối:"
    log_dns 4 | sed 's/^/    /'
fi

buoc "[BƯỚC 7] Gọi dịch vụ THẬT — và kiểm tra đúng MÁY chưa"
IFS='|' read -r CODE RIP RC <<<"$(curl_thu "$TEN_HOI")"
PAGE=$(noi_dung_trang "$TEN_HOI")
echo "  curl http://$TEN_HOI/  ->  http_code=$CODE  exit=$RC  kết nối tới ${RIP:-(không tới đâu)}"
echo "  trang nhận được        :  ${PAGE:-(không có)}"
echo ""
case "$RC" in
    0)  if [ "$RIP" = "$IP_WEB" ]; then
            echo "  ✅ HTTP $CODE từ đúng máy $IP_WEB. Dịch vụ khỏe."
        else
            echo "  ⚠️  HTTP $CODE — NHƯNG từ $RIP, không phải $IP_WEB."
            echo "     Đây là ca nguy hiểm nhất: giám sát uptime báo MÀU XANH trong khi"
            echo "     người dùng đang xem nhầm server. -> MR4-A hoặc KB3 hoặc MR5."
        fi ;;
    6)  echo "  ❌ curl exit 6 'Could not resolve host' — chết ở khâu PHÂN GIẢI."
        echo "     Chú ý: exit 6 xuất hiện ở CẢ MR1 (bị từ chối) LẪN MR2 (NXDOMAIN)."
        echo "     curl KHÔNG đủ để chẩn đoán. Đọc lại bước 4." ;;
    28) echo "  ❌ curl exit 28 TIMEOUT. Nhưng timeout ở KHÂU NÀO?"
        echo "     Nếu bước 4 không ra IP  -> chết lúc PHÂN GIẢI  (KB2)."
        echo "     Nếu bước 4 CÓ ra IP     -> phân giải xong rồi, chết lúc KẾT NỐI TCP"
        echo "                                tới địa chỉ đó (MR4-B). Kiểm bằng curl -v:"
        echo "                                có in được dòng 'Trying <ip>:80' không." ;;
    7)  echo "  ❌ curl exit 7 CONNECTION REFUSED — tên phân giải OK, máy có thật,"
        echo "     nhưng không ai nghe cổng 80. Không phải ca bệnh DNS." ;;
    *)  echo "  ❌ curl exit $RC." ;;
esac

echo ""
echo "=========================================="
echo "🔑 BẢNG VÂN TAY — dán lên tường"
echo "=========================================="
cat <<'BANG'
  dig                      curl      NSS vs dig   -> Ca bệnh
  ------------------------ --------- ------------ ---------------------------
  NOERROR, IP đúng         200       khớp         KHỎE
  timed out (~2000ms)      exit 28   -            KB2 resolver không tới được
                                                  (log server: 0 query)
  timed out (~2000ms)      exit 6    -            MR3 forwarder chết
                                                  (log server: CÓ query)
  connection refused (~20ms) exit 6  -            MR1 dịch vụ DNS chết
  NXDOMAIN (~0ms)          exit 6    -            MR2 không có bản ghi
  NOERROR, IP SAI          200/28    khớp         MR4 DNS trả sai địa chỉ
  NOERROR, IP đúng         200       LỆCH         KB3 /etc/hosts đè lên
  NOERROR, IP MỚI          200       LỆCH (cũ)    MR5 bộ đệm giữ IP cũ
BANG
[ "$L3" = "0" ] && echo "" && echo "⚠️  Nhắc lại: BƯỚC 1 thất bại. Mọi kết luận trên đều vô nghĩa khi L3 đang chết."
exit 0
