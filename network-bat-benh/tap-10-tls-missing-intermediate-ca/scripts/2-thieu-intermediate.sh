#!/usr/bin/env bash
# ==============================================================================
# KB2 — ⭐ SERVER GUI THIEU INTERMEDIATE.  Chu ky: 1 cert, num=20, DEPTH=0.
#
# Day la ca benh dat ten cho ca tap. nginx tro `ssl_certificate` vao file chi
# chua LEAF, thay vi file gop leaf+intermediate.
#
# Tinh huong ngoai doi — gan nhu luon la mot trong hai cai nay:
#   • Let's Encrypt sinh ra 4 file trong /etc/letsencrypt/live/<domain>/:
#         cert.pem       = CHI leaf          <- tro vao day la dinh KB2
#         chain.pem      = chi intermediate
#         fullchain.pem  = leaf + intermediate  <- PHAI dung cai nay
#         privkey.pem
#     Ten `cert.pem` nghe hop ly nhat trong bon cai, va no la cai SAI.
#   • Mua cert tu CA thuong mai: ho gui mot file .crt va mot file .ca-bundle
#     roi email dinh kem, nhieu nguoi upload moi file .crt.
#
# ⚠️ VI SAO "MAY EM TEST VAN CHAY"?
#    Trinh duyet tren may da tung vao mot site khac dung CUNG intermediate do se
#    CACHE lai cert trung gian, va lan sau tu va chuoi giup server. May cua ky su
#    (duyet web ca ngay) gan nhu chac chan co cache. Dien thoai vua khoi dong,
#    container CI vua tao, may khach hang lan dau vao site thi KHONG co.
#    Cung mot server, cung mot chuoi thieu — hai ket qua khac nhau.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "🚨 KB2 — nginx chỉ gửi LEAF (serveronly.crt), không gửi kèm intermediate..."
cai_root          # trust store CLIENT hoan toan binh thuong — loi khong nam o day
dat_chuoi thieu-int

buoc "CHỮ KÝ: SERVER GỬI THIẾU"
in_chu_ky
echo ""
echo "👉 Đọc chữ ký:"
echo "   • Số cert trên dây tụt từ 2 xuống 1. Đó là triệu chứng nhìn thấy ngay."
echo "   • num=20 DEPTH=0 — cert hỏng là LEAF. Trong những gì server gửi ra,"
echo "     không có ai bảo lãnh cho nó."
echo "   • Trust store của client vẫn CÓ root — nó không hề có lỗi. Đổi máy"
echo "     client ở đây là chữa nhầm người."
echo "   • Chữa: trỏ ssl_certificate sang fullchain.crt. Một dòng cấu hình."
echo ""
echo "   ⚠️ Hãy nhớ ĐÚNG DÒNG CHỮ này: 'unable to get local issuer certificate'."
echo "      KB3 sẽ in ra y hệt, với cùng mã 20 — và thủ phạm ngược lại hoàn toàn."
