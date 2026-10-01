FROM alpine:3.20
# Day la "NAT Gateway" that cua lab: forward + MASQUERADE giua LAN client va
# WAN server, giu bang conntrack -- noi toan bo ca benh cua tap nay song o do.
RUN apk add --no-cache iptables iproute2 conntrack-tools tcpdump bash
CMD ["sleep", "infinity"]
