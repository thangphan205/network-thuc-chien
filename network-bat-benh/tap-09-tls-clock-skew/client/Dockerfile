FROM alpine:3.23
# ==============================================================================
# MAY CLIENT — "nan nhan" cua tap 09.
#
# ⚠️ VI SAO DUNG faketime CHU KHONG DOI DONG HO CONTAINER?
#    Container KHONG co dong ho rieng. No dung chung dong ho cua kernel voi may
#    that. `date -s` trong container (neu duoc cap CAP_SYS_TIME) se doi gio MAY
#    THAT cua hoc vien — hong lich, hong chung chi that, hong ca phien lam viec.
#    libfaketime chen qua LD_PRELOAD va chi lua DUNG tien trinh duoc goi. An
#    toan tuyet doi, va tat khi tien trinh ket thuc.
#    Vi vay compose KHONG cap CAP_SYS_TIME cho container nay.
#
# Cong cu:
#   curl        — goc nhin cua UNG DUNG (co kiem tra ten mien)
#   openssl     — goc nhin cua KY THUAT VIEN (mac dinh KHONG kiem tra ten mien)
#                 Khac biet giua hai goc nhin nay chinh la ca benh MR2.
#   libfaketime — gia lap lech gio
#   chrony      — hoi gio that (chronyd -Q, chi DOC, khong dat lai dong ho)
#   iptables    — MR5 chan UDP 123
#   tcpdump     — bat goi TLS trong container (chay giong nhau tren mac/win/linux)
# ==============================================================================
#   ca-certificates — de CAI CA CUA LAB VAO TRUST STORE cua may (0-setup lam viec
#                 nay). Nho vay hoc vien go `curl https://secure.local/` tran, dung
#                 y het ngoai doi, khong phai dinh kem --cacert vao moi lenh. Va
#                 MR3 (cert tu ky) moi that su that bai vi KHONG AI TIN NGUOI KY,
#                 chu khong phai vi quen mot tham so dong lenh.
RUN apk add --no-cache curl openssl libfaketime chrony iptables tcpdump ca-certificates tzdata

COPY monitor.sh /usr/local/bin/monitor.sh
COPY phien-dai.sh /usr/local/bin/phien-dai.sh
RUN chmod 0755 /usr/local/bin/monitor.sh /usr/local/bin/phien-dai.sh

CMD ["sleep", "infinity"]
