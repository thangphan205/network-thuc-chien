FROM alpine:latest
# openssl >= 3.4 de dung duoc -not_before / -not_after (sinh cert het han co dinh)
RUN apk add --no-cache openssl
COPY gen-certs.sh /gen-certs.sh
RUN chmod +x /gen-certs.sh
ENTRYPOINT ["/gen-certs.sh"]
