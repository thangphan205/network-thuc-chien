# ==============================================================================
# LOAD BALANCER NODE: HAProxy + Keepalived
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
    haproxy \
    keepalived \
    iproute2 \
    iptables \
    iputils \
    curl \
    tcpdump \
    bash \
    procps

# ------------------------------------------------------------------------------
# Health-check cho Keepalived.
# PHẢI bake vào image với quyền root:root 0755. Nếu bind-mount từ host, file sẽ
# mang UID của user host và Keepalived (bật enable_script_security) sẽ từ chối:
#   "Unsafe permissions found for script ... - disabling"
# -> track_script bị vô hiệu hoá âm thầm, HAProxy chết mà VIP vẫn nằm im.
# ------------------------------------------------------------------------------
RUN printf '%s\n' \
    '#!/bin/sh' \
    '# Còn phục vụ được HTTP qua HAProxy thì trả 0, ngược lại trả 1.' \
    'curl -sf --max-time 1 -o /dev/null http://127.0.0.1:80/ || exit 1' \
    'exit 0' \
    > /usr/local/bin/check_haproxy.sh \
 && chmod 0755 /usr/local/bin/check_haproxy.sh \
 && chown root:root /usr/local/bin/check_haproxy.sh

COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ka-start.sh /usr/local/bin/ka-start
COPY ka-stop.sh  /usr/local/bin/ka-stop
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/ka-start /usr/local/bin/ka-stop \
 && mkdir -p /etc/keepalived /run/haproxy

EXPOSE 80 8404
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
