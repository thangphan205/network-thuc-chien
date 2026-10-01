#!/usr/bin/env bash
# ==============================================================================
# MR8 — "TOI SUA ROI MA VAN LOI": file dung, tien trinh cu.
#
# Kich ban ngan nhat trong tap, va co le la ca benh ban se gap NHIEU LAN NHAT
# trong doi that — thuong la luc 2 gio sang, dang xu ly su co that.
#
# Dien bien:
#   1. Cau hinh dang hong (chuoi thieu intermediate) — KB2.
#   2. Ban sua file: tro sang chuoi day du. File tren dia gio DUNG.
#   3. Ban quen reload nginx.
#   4. Moi cong cu doc FILE deu bao "da sua roi". Moi client doc DAY deu bao
#      "van hong". Va hai ben cai nhau ca buoi chieu.
#
# ⚠️ VI SAO NO SONG DAI DEN THE:
#    Vi nguoi sua va nguoi bao loi dung HAI NGUON SU THAT khac nhau, va ca hai
#    deu dang noi that. `cat /etc/nginx/conf.d/*.conf` khong bao gio phan anh
#    thu dang chay — no phan anh thu SE chay o lan khoi dong toi.
#
# 🧠 QUY TAC: khong bao gio xac nhan mot thay doi TLS bang cach doc file cau
#    hinh. Luon xac nhan bang mot lan BAT TAY THAT tu ben ngoai:
#        echo | openssl s_client -connect host:443 -showcerts
#    Do la ly do `xem-chuoi.sh` co dung hai cot: "conf tren DIA" va "chuoi TREN DAY".
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "🚨 MR8 — buoc 1: dat lab vao trang thai hong (thieu intermediate)..."
cai_root
dat_chuoi thieu-int

buoc "TRUOC KHI SUA"
RAW=$(_bat_tay)
echo "  Chuoi trong conf (tren DIA) : $(chuoi_dang_dat)"
echo "  So cert TREN DAY            : $(so_cert_gui "$RAW")"
IFS='|' read -r NUM DEPTH MSG <<<"$(verify_chi_tiet "$RAW")"
echo "  openssl verify              : num=$NUM DEPTH=$DEPTH"

echo ""
echo "🔧 buoc 2: sua file cau hinh sang chuoi day du — VA CO TINH QUEN RELOAD..."
dat_chuoi_khong_reload good

buoc "SAU KHI SUA FILE, TRUOC KHI RELOAD"
RAW=$(_bat_tay)
IFS='|' read -r NUM DEPTH MSG <<<"$(verify_chi_tiet "$RAW")"
IFS='|' read -r CODE RC CMSG <<<"$(curl_thu)"
echo "  Chuoi trong conf (tren DIA) : $(chuoi_dang_dat)      <- DA SUA, dang dung"
echo "  So cert TREN DAY            : $(so_cert_gui "$RAW")                      <- VAN CU"
echo "  openssl verify              : num=$NUM DEPTH=$DEPTH"
echo "  curl                        : http=$CODE exit=$RC"
echo "  ---"
echo "  ❗ Hai cot dang MAU THUAN nhau. Do chinh la chu ky cua ca benh nay."
echo "     Nguoi doc file thi bao 'sua roi'. Nguoi goi API thi bao 'van hong'."
echo "     Ca hai deu dung."

echo ""
echo "🔧 buoc 3: reload that su..."
docker compose restart web-server >/dev/null 2>&1
cho_web_san_sang

buoc "SAU KHI RELOAD"
RAW=$(_bat_tay)
IFS='|' read -r NUM DEPTH MSG <<<"$(verify_chi_tiet "$RAW")"
IFS='|' read -r CODE RC CMSG <<<"$(curl_thu)"
echo "  Chuoi trong conf (tren DIA) : $(chuoi_dang_dat)"
echo "  So cert TREN DAY            : $(so_cert_gui "$RAW")"
echo "  openssl verify              : num=$NUM DEPTH=$DEPTH"
echo "  curl                        : http=$CODE exit=$RC"

echo ""
echo "👉 Doc chu ky:"
echo "   • Khong co ma loi rieng cho ca benh nay. Chu ky cua no la SU MAU THUAN"
echo "     giua file tren dia va chuoi tren day."
echo "   • Ngoai doi con mot bien the doc hon: da reload, nhung reload nham"
echo "     tien trinh — vi du sua cau hinh cua nginx trong khi TLS dang duoc"
echo "     terminate o load balancer phia truoc. Luc do file dung, tien trinh"
echo "     dung, ma client van thay cert cu."
echo ""
echo "   🧠 Xac nhan thay doi TLS bang bat tay that, khong bang doc file:"
echo "        echo | openssl s_client -connect host:443 -showcerts 2>/dev/null \\"
echo "          | grep -c 'BEGIN CERTIFICATE'"
