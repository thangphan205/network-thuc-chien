FROM alpine:3.20
# Router + stateful firewall: forward, conntrack, iptables. Hai container nhu the
# (fw-a, fw-b) dung THAT giua client va server -> asymmetric routing that.
RUN apk add --no-cache iptables iproute2 conntrack-tools tcpdump bash
CMD ["sleep", "infinity"]
