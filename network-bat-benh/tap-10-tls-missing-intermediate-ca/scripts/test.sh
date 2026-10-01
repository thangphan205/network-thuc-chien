#!/usr/bin/env bash
# ==============================================================================
# SMOKE TEST — chay ca 7 kich ban va khang dinh tung ca ra DUNG chu ky mong doi.
#
#   ./scripts/test.sh
#
# Vi sao can file nay?
#   Vi bai hoc cua tap la mot BANG SO. Neu mot ban openssl nao do doi cach in
#   depth, hoac mot phien ban nginx moi chap nhan chuoi dao nguoc, thi README se
#   day sai ma khong ai biet. File nay bat duoc dieu do ngay.
#
# ⚠️ Moi phep thu deu chay TRONG container client. Khong dung curl/openssl cua
#    may that: macOS ship LibreSSL, Linux ship OpenSSL, hai ban in ma verify va
#    so depth theo dinh dang khac nhau — ma so depth chinh la thu dang duoc test.
# ==============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

HONG=0
PASS=0

kiem() {   # kiem <ten> <thuc_te> <mong_doi>
    if [ "$2" = "$3" ]; then
        printf "   ✅ %s%*s %s\n" "$1" $((34 - ${#1})) "" "$2"
        PASS=$((PASS + 1))
    else
        printf "   ❌ %s%*s %s   (mong đợi: %s)\n" "$1" $((34 - ${#1})) "" "$2" "$3"
        HONG=$((HONG + 1))
    fi
}

# Moi kich ban: dat trang thai, doc MOT lan bat tay, roi so voi bang mong doi.
soi() {   # soi <conf> <co_root:1|0>
    dat_chuoi "$1"
    if [ "$2" = "1" ]; then cai_root; else go_root; fi
    RAW=$(_bat_tay)
    IFS='|' read -r T_NUM T_DEPTH T_MSG <<<"$(verify_chi_tiet "$RAW")"
    IFS='|' read -r T_CODE T_RC T_CMSG <<<"$(curl_thu)"
    T_N=$(so_cert_gui "$RAW")
}

echo "=============================================="
echo "🧪 TEST TẬP 10 — bảng vân tay của 11 kịch bản"
echo "=============================================="

echo ""
echo "KB1 — chuỗi đầy đủ:"
soi good 1
kiem "số cert gửi ra dây" "$T_N"     "2"
kiem "verify num"          "$T_NUM"   "0"
kiem "curl http"           "$T_CODE"  "200"

echo ""
echo "KB2 — server gửi thiếu intermediate:"
soi thieu-int 1
kiem "số cert gửi ra dây" "$T_N"     "1"
kiem "verify num"          "$T_NUM"   "20"
kiem "⭐ verify DEPTH"      "$T_DEPTH" "0"
kiem "curl exit"           "$T_RC"    "60"

echo ""
echo "MR1 — chuỗi đảo ngược:"
dat_chuoi dao-nguoc
kiem "nginx"               "$(nginx_song)" "ĐÃ CHẾT"
if docker logs --tail 30 $WEB 2>&1 | grep -qi "key values mismatch"; then
    printf "   ✅ %s%*s %s\n" "log nginx" 25 "" "key values mismatch"; PASS=$((PASS + 1))
else
    printf "   ❌ %s%*s %s\n" "log nginx" 25 "" "không thấy 'key values mismatch'"; HONG=$((HONG + 1))
fi

echo ""
echo "MR2 — chuỗi thừa root:"
soi thua-root 1
kiem "số cert gửi ra dây" "$T_N"     "3"
kiem "verify num"          "$T_NUM"   "0"
kiem "curl http"           "$T_CODE"  "200"

echo ""
echo "MR3 — intermediate hết hạn:"
soi int-het-han 1
kiem "verify num"          "$T_NUM"   "10"
kiem "⭐ verify DEPTH"      "$T_DEPTH" "1"
kiem "curl exit"           "$T_RC"    "60"

echo ""
echo "KB3 — client thiếu root  (⭐ cặp đôi với KB2):"
soi good 0
kiem "số cert gửi ra dây" "$T_N"     "2"
kiem "verify num"          "$T_NUM"   "20"
kiem "⭐ verify DEPTH"      "$T_DEPTH" "1"
kiem "curl exit"           "$T_RC"    "60"

echo ""
echo "MR4 — chỉ gửi leaf, nhưng leaf có AIA:"
soi aia 1
kiem "số cert gửi ra dây" "$T_N"     "1"
kiem "verify num"          "$T_NUM"   "20"
URL=$(aia_url "$RAW")
kiem "có URL AIA trong cert" "$([ -n "$URL" ] && echo CO || echo KHONG)" "CO"
_trong_client "curl -s -o /tmp/int.der '$URL'" >/dev/null
_trong_client "openssl x509 -inform DER -in /tmp/int.der -out /tmp/int.pem" >/dev/null
_trong_client "echo | openssl s_client -connect $IP_WEB:443 -servername $TEN 2>/dev/null | sed -n '/BEGIN CERT/,/END CERT/p' > /tmp/leaf.pem" >/dev/null
AIA_OK=$(_trong_client "openssl verify -CAfile $TRUST -untrusted /tmp/int.pem /tmp/leaf.pem 2>&1 | grep -c ': OK'" | tr -d ' ')
kiem "verify sau khi tải AIA"  "$AIA_OK" "1"

echo ""
echo "MR5 — 2 cert nhưng sai người ký  (phá luật \"đếm cert\"):"
soi sai-int 1
kiem "số cert gửi ra dây" "$T_N"     "2"
kiem "verify num"          "$T_NUM"   "20"
kiem "⭐ verify DEPTH"      "$T_DEPTH" "0"
MX=$(kiem_mat_xich "$RAW" | grep -c 'ĐỨT MẮT XÍCH' || true)
kiem "phát hiện đứt mắt xích" "$MX"   "1"

echo ""
echo "MR6 — cross-sign, hai máy hai kết quả:"
dat_chuoi cross-sign
cai_root
RAW=$(_bat_tay)
kiem "số cert gửi ra dây" "$(so_cert_gui "$RAW")" "3"
_trong_client "echo | openssl s_client -connect $IP_WEB:443 -servername $TEN -showcerts 2>/dev/null | sed -n '/BEGIN CERT/,/END CERT/p' > /tmp/x.pem" >/dev/null
_trong_client "awk 'BEGIN{n=0} /BEGIN CERT/{n++} {print > (\"/tmp/x\" n \".pem\")}' /tmp/x.pem" >/dev/null
MOI=$(_trong_client "openssl verify -CAfile /etc/ssl/lab/rootMoi.crt -untrusted /tmp/x2.pem -untrusted /tmp/x3.pem /tmp/x1.pem 2>&1 | grep -c ': OK'" | tr -d ' ')
kiem "máy MỚI  -> OK"      "$MOI"    "1"
CU=$(_trong_client "openssl verify -CAfile /etc/ssl/lab/rootCu.crt -untrusted /tmp/x2.pem -untrusted /tmp/x3.pem /tmp/x1.pem 2>&1 | sed -n 's/^error \\([0-9]*\\) at \\([0-9]*\\) depth.*/\\1@\\2/p' | head -1")
kiem "máy CŨ   -> hết hạn ở depth cao" "$CU" "10@3"

echo ""
echo "MR7 — trust store của RUNTIME (không phải của HĐH):"
dat_chuoi good
cai_root
cai_root_node
A_CURL=$(_trong_client "curl -s -o /dev/null -w '%{http_code}' https://$TEN/ || echo 000")
kiem "alpine  curl"        "$A_CURL"  "200"
D_CURL=$(docker exec $CLIENT_NODE sh -c "curl -s -o /dev/null -w '%{http_code}' https://$TEN/ || echo 000" 2>/dev/null)
kiem "debian  curl"        "$D_CURL"  "200"
D_NODE=$(docker exec $CLIENT_NODE node -e "fetch('https://$TEN/').then(r=>console.log(r.status)).catch(e=>console.log('FAIL'))" 2>/dev/null)
kiem "debian  node (phải HỎNG)" "$D_NODE" "FAIL"
D_NODE2=$(docker exec -e NODE_EXTRA_CA_CERTS=$ROOT_TRONG_CLIENT $CLIENT_NODE node -e "fetch('https://$TEN/').then(r=>console.log(r.status)).catch(e=>console.log('FAIL'))" 2>/dev/null)
kiem "debian  node + EXTRA_CA" "$D_NODE2" "200"

echo ""
echo "MR8 — sửa file mà không reload:"
dat_chuoi thieu-int
cai_root
dat_chuoi_khong_reload good
RAW=$(_bat_tay)
kiem "conf trên ĐĨA đã đổi"  "$(chuoi_dang_dat)" "chuoi_daydu.crt"
kiem "chuỗi TRÊN DÂY vẫn cũ" "$(so_cert_gui "$RAW")" "1"
dat_chuoi good
RAW=$(_bat_tay)
kiem "sau reload mới đổi"    "$(so_cert_gui "$RAW")" "2"

echo ""
echo "🔧 Đưa lab về trạng thái bình thường..."
cai_root >/dev/null
dat_chuoi good >/dev/null

echo ""
echo "=============================================="
if [ "$HONG" -eq 0 ]; then
    echo "✅ TẤT CẢ $PASS PHÉP THỬ ĐỀU ĐÚNG."
    echo ""
    echo "   ⭐ Hai dòng đáng giá nhất vừa chạy qua:"
    echo "        KB2  num=20  DEPTH=0  ->  SERVER gửi thiếu"
    echo "        KB3  num=20  DEPTH=1  ->  CLIENT thiếu root"
    exit 0
else
    echo "❌ $HONG PHÉP THỬ SAI (và $PASS đúng)."
    echo "   Bảng vân tay trong README đang không khớp với lab — sửa trước khi dạy."
    exit 1
fi
