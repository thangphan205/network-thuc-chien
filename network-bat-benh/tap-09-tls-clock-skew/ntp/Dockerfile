# ==============================================================================
# NGUON GIO THAT CUA LAB.
#
# Ton tai de tra loi cau hoi trung tam cua tap: "dong ho cua ai dang sai?"
# Muon tra loi duoc thi phai co mot nguon gio KHONG PHAI la dong ho cua client.
#
# Dung NTP server trong lab chu khong dung pool.ntp.org:
#   - lab chay duoc ca khi may hoc vien rut mang,
#   - MR5 chan duoc UDP 123 mot cach dut khoat (chan trong bridge cua lab),
#   - moi hoc vien thay cung mot ket qua.
# ==============================================================================
FROM alpine:3.23
RUN apk add --no-cache chrony tzdata
COPY chrony.conf /etc/chrony/chrony.conf
# -d: chay foreground de chronyd la PID 1 va `docker compose logs ntp` bat duoc log.
# -x: KHONG dieu khien dong ho he thong.
#     BAT BUOC trong container. Container dung chung dong ho kernel voi may that,
#     ma no khong duoc cap CAP_SYS_TIME. Thieu -x, chronyd goi adjtimex() ngay khi
#     khoi dong, bi tu choi, va CHET voi:
#         Fatal error : adjtimex(0x8001) failed : Operation not permitted
#     Container tat ngay, `docker compose ps` khong hien no, va MR5 im lang bao
#     "khong hoi duoc nguon gio" o CA HAI ve — tuc la mat sach kha nang doi chung.
CMD ["chronyd", "-d", "-x", "-f", "/etc/chrony/chrony.conf"]
