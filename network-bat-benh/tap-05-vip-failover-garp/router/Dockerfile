# ==============================================================================
# ROUTER 3 CHAN: dong vai router/firewall doanh nghiep dung giua 3 tang mang.
#
#   iproute2  -> ip route / ip neigh (xem va xoa bang ARP - o benh cua tap nay)
#   iptables  -> kich ban 11: chan .52 -> .53 lam HAProxy mat backend
#   tcpdump   -> chung minh GARP DUNG LAI o bien L3, khong xuyen sang client LAN
#   iputils   -> ping / arping doi chieu
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache iproute2 iptables iputils tcpdump curl

CMD ["sleep", "infinity"]
