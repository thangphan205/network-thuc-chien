FROM alpine:latest
RUN apk add --no-cache openssl
COPY gen-certs.sh /gen-certs.sh
RUN chmod +x /gen-certs.sh
ENTRYPOINT ["/gen-certs.sh"]
