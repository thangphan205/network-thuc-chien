#!/usr/bin/env bash
# ==============================================================================
# CA BI AN — gieo NGAU NHIEN mot ca benh trong KB2-KB8, KHONG in loi giai.
# Hoc vien tu chan doan bang cac cong cu da hoc, tu chua, tu kiem: truy cap duoc
# web la xong.
#
#   ./scripts/ca-bi-an.sh            # gieo ngau nhien
#   ./scripts/ca-bi-an.sh <ca>       # (giang vien) ep mot ca: 2 3 4 5 6A 6B 7 8
#
# Ca benh dung ten $TEN_BI_AN trong vung rieng $VUNG_BI_AN — KHONG trung ten nao
# cua KB2-KB8, nen ten mien khong goi y dap an. Vung nay chi ton tai LUC CHAY
# (ghi vao conf/zone dang chay); 0-setup.sh chep ban .default de len la xoa sach.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

CAC_CA=(2 3 4 5 6A 6B 7 8)
CA=${1:-${CAC_CA[RANDOM % ${#CAC_CA[@]}]}}
case "$CA" in
    2|3|4|5|6A|6B|7|8) ;;
    *) echo "❌ Ca không hợp lệ: $CA (chọn một trong: ${CAC_CA[*]})"; exit 1 ;;
esac

echo "🎲 Đang dựng lab và gieo một ca bệnh ngẫu nhiên..."
if ! ./scripts/0-setup.sh >/dev/null 2>&1; then
    echo "❌ 0-setup.sh thất bại — chạy riêng ./scripts/0-setup.sh để xem lỗi."
    exit 1
fi

# --- Vung bi an o trang thai KHOE: dnsmasq co tham quyen cho $VUNG_BI_AN -------
docker exec $DNS sh -c "printf 'local=/%s/\n' '$VUNG_BI_AN' >> $CONF"
doi_ban_ghi "$TEN_BI_AN" "$IP_WEB"
sleep 1
IFS='|' read -r CODE RIP _ <<<"$(curl_thu "$TEN_BI_AN")"
if [ "$CODE" != "200" ] || [ "$RIP" != "$IP_WEB" ]; then
    echo "❌ Không dựng được trạng thái khoẻ cho $TEN_BI_AN (http_code=$CODE, IP=${RIP:-?})."
    exit 1
fi

xoa_ban_ghi_bi_an() {
    docker exec $DNS sh -c "grep -v '[[:space:]]$TEN_BI_AN[[:space:]]' $ZONE > /tmp/z; cp /tmp/z $ZONE"
}

# Xac nhan CA BENH bang CHU KY quan sat duoc, khong chi dua vao ma thoat cua lenh
# gay benh. Moi kiem tra deu im lang va log DNS se duoc xoa ngay sau do, nen hoc
# vien khong nhan them manh moi nao ve ca vua duoc gieo.
xac_nhan_ca_bi_an() {
    local raw st dip nss ns q a code rip rc

    case "$CA" in
        2)
            ns=$(docker exec $CLIENT sh -c "awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf" 2>/dev/null | tr -d '\r')
            raw=$(dig_full "$TEN_BI_AN")
            st=$(dig_status_tu "$raw")
            [ "$ns" = "$IP_MA" ] && [ "$st" = "$KHONG_TL" ]
            ;;
        3)
            docker exec $DNS true >/dev/null 2>&1 && \
                ! docker exec $DNS pgrep -x dnsmasq >/dev/null 2>&1
            ;;
        4)
            raw=$(dig_full "$TEN_BI_AN")
            st=$(dig_status_tu "$raw")
            q=$(dem_query_o_server)
            a=$(dem_tra_loi_ten "$TEN_BI_AN")
            [ "$st" = "$KHONG_TL" ] && [ "${q:-0}" -gt 0 ] && [ "${a:-0}" = "0" ]
            ;;
        5)
            raw=$(dig_full "$TEN_BI_AN")
            [ "$(dig_status_tu "$raw")" = "NXDOMAIN" ]
            ;;
        6A)
            dip=$(ip_theo_dig "$TEN_BI_AN")
            IFS='|' read -r code rip rc <<<"$(curl_thu "$TEN_BI_AN")"
            [ "$dip" = "$IP_WEB_CU" ] && [ "$code" = "200" ] && [ "$rip" = "$IP_WEB_CU" ] && [ "$rc" = "0" ]
            ;;
        6B)
            [ "$(ip_theo_dig "$TEN_BI_AN")" = "$IP_MA" ]
            ;;
        7)
            dip=$(ip_theo_dig "$TEN_BI_AN")
            nss=$(ip_theo_nss "$TEN_BI_AN")
            [ "$dip" = "$IP_WEB" ] && [ "$nss" = "$IP_WEB_CU" ]
            ;;
        8)
            docker exec $CLIENT pgrep -x nscd >/dev/null 2>&1 || return 1
            dip=$(ip_theo_dig "$TEN_BI_AN")
            nss=$(ip_theo_nss "$TEN_BI_AN")
            IFS='|' read -r code rip rc <<<"$(curl_thu "$TEN_BI_AN")"
            [ "$dip" = "$IP_WEB" ] && [ "$nss" = "$IP_WEB_CU" ] && \
                [ "$code" = "200" ] && [ "$rip" = "$IP_WEB_CU" ] && [ "$rc" = "0" ]
            ;;
    esac
}

# --- Gay benh. Moi output deu nuot: man hinh KHONG duoc lo ca nao -------------
{
case "$CA" in
    2)  dat_resolv "$IP_MA" ;;
    3)  docker exec $DNS dns-stop ;;
    4)  # Vung bi an chuyen tiep sang may chet. Phai xoa ca ban ghi: dnsmasq tra
        # loi tu addn-hosts TRUOC khi xet server=, con ban ghi thi khong bao gio forward.
        docker exec $DNS sh -c "cp /etc/dnsmasq/dnsmasq.conf.default $CONF && printf 'server=/%s/%s\n' '$VUNG_BI_AN' '$IP_MA' >> $CONF"
        xoa_ban_ghi_bi_an
        nap_lai_dns ;;
    5)  # Giu local= -> ten vang mat trong zone = NXDOMAIN ngay ("thieu ban ghi")
        xoa_ban_ghi_bi_an
        nap_lai_dns ;;
    6A) doi_ban_ghi "$TEN_BI_AN" "$IP_WEB_CU" ;;
    6B) doi_ban_ghi "$TEN_BI_AN" "$IP_MA" ;;
    7)  them_hosts "$IP_WEB_CU" "$TEN_BI_AN" ;;
    8)  # Nhu 8-cache-cu.sh, nhung giu cache 3600 s: hoc vien do benh mat vai
        # phut, cache het han giua chung thi ca benh TU KHOI va danh lua nguoi do.
        # nscd lay TTL NHO HON giua positive-time-to-live va TTL ban ghi DNS
        # -> phai nang CA HAI (xem dat_local_ttl trong lib.sh).
        dat_local_ttl 3600
        doi_ban_ghi "$TEN_BI_AN" "$IP_WEB_CU"
        sleep 1
        docker exec $CLIENT sh -c "pkill -x nscd; rm -f /var/db/nscd/*; \
            sed 's/^\(\s*positive-time-to-live\s\+hosts\s\+\).*/\1 3600/' /etc/nscd.conf > /tmp/nscd-bi-an.conf; \
            nscd -f /tmp/nscd-bi-an.conf" || true
        sleep 1
        # Ham nong CA HAI khoa cua nscd (getent = IPv4 thuan, curl = AF_UNSPEC) — xem 8-cache-cu.sh
        docker exec $CLIENT getent hosts "$TEN_BI_AN" || true
        docker exec $CLIENT curl -s -o /dev/null --max-time 3 "http://$TEN_BI_AN/" || true
        dat_local_ttl 30
        doi_ban_ghi "$TEN_BI_AN" "$IP_WEB" ;;
esac
} >/dev/null 2>&1
sleep 1

# Bo log cua buoc setup/gay benh de validator chi doc dung probe cua chinh no.
xoa_log_dns

if ! xac_nhan_ca_bi_an; then
    ./scripts/0-setup.sh >/dev/null 2>&1 || true
    echo "❌ Không gieo được ca bệnh ổn định. Lab đã được đưa về trạng thái sạch; hãy chạy lại."
    exit 1
fi

# Validator co the tu tao query/log de doc chu ky; xoa het truoc khi giao lab.
xoa_log_dns

cat <<PHIEU

==========================================
📟 PHIẾU BÁO BỆNH
==========================================
  Người dùng trên máy $CLIENT báo:
    "Vào http://$TEN_BI_AN không được như mọi khi."

  Thông tin đúng của dịch vụ:
    $TEN_BI_AN  ->  $IP_WEB   (trang 'SERVER MỚI')

  Nhiệm vụ:
    1. Tìm ra ca bệnh — dựa trên các kịch bản KB2–KB8 đã học.
    2. Chữa ĐÚNG CHỖ: trên máy client hay trên DNS server?
    3. Tự kiểm khi xong:
         docker exec $CLIENT curl -s http://$TEN_BI_AN/
       phải ra trang SERVER MỚI, từ $IP_WEB.

  Công cụ (nhớ truyền tên $TEN_BI_AN):
    docker exec -it $CLIENT monitor.sh $TEN_BI_AN
    ./scripts/xem-log-dns.sh
    ./scripts/bat-goi-dns.sh 12 $TEN_BI_AN
    docker exec -it $CLIENT bash          # dig, getent, curl -v, cat /etc/resolv.conf ...
    docker exec -it $DNS sh               # $CONF, $ZONE, dns-start

  Phao cứu sinh (chỉ dùng sau cùng):  ./scripts/test.sh $TEN_BI_AN

  ⚠️  KHÔNG dùng ./scripts/0-setup.sh để "chữa": nó xoá luôn vùng $VUNG_BI_AN,
      $TEN_BI_AN sẽ không còn tồn tại.
  🎲 Ván mới: ./scripts/ca-bi-an.sh      Về lab sạch: ./scripts/0-setup.sh
PHIEU
