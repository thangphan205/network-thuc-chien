FROM alpine:3.20
# Bake sẵn công cụ để không phải `apk add` giữa lúc quay demo
RUN apk add --no-cache iproute2 iputils curl tcpdump bash
COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod 0755 /usr/local/bin/monitor.sh
# Không cần CMD: docker-compose.yml đã đặt `command: sleep infinity`
