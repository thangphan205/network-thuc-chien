FROM alpine:3.23
RUN apk add --no-cache openssl
COPY gen-certs.sh /gen-certs.sh
RUN chmod +x /gen-certs.sh
ENTRYPOINT ["/gen-certs.sh"]
