#!/usr/bin/env bash
# ==============================================================================
# KEEPALIVED HEALTH CHECK SCRIPT FOR NGINX
# Path: /etc/keepalived/check_nginx.sh
# Permission: chmod +x /etc/keepalived/check_nginx.sh
# ==============================================================================
set -e

# Kiểm tra process nginx hoặc gọi localhost port 80
if curl -s --max-time 1 -o /dev/null http://127.0.0.1:80/; then
    exit 0
else
    exit 1
fi
