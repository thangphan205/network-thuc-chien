# ==============================================================================
# DOCKERFILE CHO HA NODE & CLIENT TRONG CONTAINERLAB
# Tích hợp: Nginx, Keepalived, IPRoute2, iputils (arping), Curl, Tcpdump
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
    iproute2 \
    iputils \
    curl \
    tcpdump \
    nginx \
    keepalived \
    bash \
    procps \
    coreutils

# Thư mục web và runtime cho nginx/keepalived
RUN mkdir -p /var/www/html /run/nginx /etc/keepalived

# ------------------------------------------------------------------------------
# Health-check script cho keepalived.
# PHẢI bake vào image (root:root, 0755). Nếu bind-mount từ host thì file sẽ mang
# UID của user host -> keepalived bật `enable_script_security` sẽ từ chối chạy:
#   "Unsafe permissions found for script ... - disabling"
# ------------------------------------------------------------------------------
RUN printf '%s\n' \
    '#!/bin/sh' \
    '# Trả 0 nếu nginx còn phục vụ, 1 nếu chết.' \
    'curl -sf --max-time 1 -o /dev/null http://127.0.0.1:80/ || exit 1' \
    'exit 0' \
    > /etc/keepalived/check_nginx.sh \
 && chmod 0755 /etc/keepalived/check_nginx.sh \
 && chown root:root /etc/keepalived/check_nginx.sh

# ------------------------------------------------------------------------------
# Nginx: site mặc định của Alpine trả 404 cho mọi request và root trỏ vào
# /var/www/localhost/htdocs. Ghi đè để phục vụ /var/www/html.
# Từng server sẽ bind-mount đè file này để thêm header X-Backend-Server riêng.
# ------------------------------------------------------------------------------
RUN printf '%s\n' \
    'server {' \
    '    listen 80 default_server;' \
    '    root /var/www/html;' \
    '    index index.html;' \
    '    add_header X-Backend-Server $hostname always;' \
    '}' \
    > /etc/nginx/http.d/default.conf

# Tắt access log ra stdout để tránh rác console
RUN sed -i 's|access_log /var/log/nginx/access.log main;|access_log off;|' /etc/nginx/nginx.conf

WORKDIR /root
CMD ["/bin/bash"]
