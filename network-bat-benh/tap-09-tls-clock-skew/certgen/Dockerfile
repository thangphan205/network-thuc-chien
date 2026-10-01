# ==============================================================================
# alpine PIN CUNG phien ban, khong dung :latest.
#
# Ly do: gen-certs.sh dung `openssl x509 -not_before/-not_after`, hai tuy chon
# CHI co tu OpenSSL 3.4. Voi :latest, lab phu thuoc vao viec Alpine tinh co dang
# ship phien ban nao — mot ngay dep troi no doi la lab hong ma khong ai sua gi.
# alpine:3.23 ship OpenSSL 3.5.x.
# ==============================================================================
FROM alpine:3.23
RUN apk add --no-cache openssl
COPY gen-certs.sh /gen-certs.sh
RUN chmod +x /gen-certs.sh
ENTRYPOINT ["/gen-certs.sh"]
