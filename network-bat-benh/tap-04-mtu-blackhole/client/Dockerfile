FROM alpine:latest
# Bake sẵn công cụ để không phải `apk add` giữa lúc quay demo
RUN apk add --no-cache iputils curl iproute2 tcpdump iptables ethtool
CMD ["sleep", "infinity"]
