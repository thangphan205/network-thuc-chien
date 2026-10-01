#!/usr/bin/env sh
# UDP echo don gian cho MR2 (NAT timeout UDP ngan hon TCP rat nhieu)
socat -T3600 UDP4-RECVFROM:9,fork,reuseaddr SYSTEM:'cat' &
exec nginx -g 'daemon off;'
