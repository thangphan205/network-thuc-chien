FROM alpine:3.20
# Bake san cong cu de khong phai `apk add` giua luc quay demo
RUN apk add --no-cache dnsmasq bind-tools tcpdump

# Ban CHUAN cua cau hinh + zone. Script `0-setup.sh` chep 2 file nay de len ban
# dang chay moi lan reset, nen moi kich ban deu xuat phat tu cung mot diem.
COPY dnsmasq.conf /etc/dnsmasq/dnsmasq.conf.default
COPY zone-hosts   /etc/dnsmasq/zone-hosts.default
COPY dns-start /usr/local/bin/dns-start
COPY dns-stop  /usr/local/bin/dns-stop
RUN chmod 0755 /usr/local/bin/dns-start /usr/local/bin/dns-stop \
 && cp /etc/dnsmasq/dnsmasq.conf.default /etc/dnsmasq/dnsmasq.conf \
 && cp /etc/dnsmasq/zone-hosts.default   /etc/dnsmasq/zone-hosts
# Khong dat CMD: docker-compose.yml da dat `command: sleep infinity`
