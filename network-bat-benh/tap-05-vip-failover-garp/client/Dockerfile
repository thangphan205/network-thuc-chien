FROM alpine:latest
# Bake sẵn công cụ để không phải `apk add` giữa lúc quay demo
RUN apk add --no-cache iproute2 iputils curl tcpdump
# Không cần CMD: docker-compose.yml đã đặt `command: sleep infinity` cho service client
