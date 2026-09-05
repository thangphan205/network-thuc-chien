# ==============================================================================
# BACKEND WEB: nginx, gắn header X-Web-Server để biết HAProxy đẩy về máy nào
# ==============================================================================
FROM nginx:alpine
ARG WEB_NAME=web

# Backend nam o tang app RIENG (172.28.53.0/24), duong ve LB LAN phai di qua
# router -> can iproute2 de cai route tinh trong 0-setup.sh.
RUN apk add --no-cache iproute2 curl

RUN printf '%s\n' \
    'server {' \
    '    listen 80 default_server;' \
    '    root /usr/share/nginx/html;' \
    '    index index.html;' \
    "    add_header X-Web-Server \"${WEB_NAME}\" always;" \
    '' \
    '    # Bóp băng thông Ở PHÍA SERVER cho file lớn.' \
    '    # Bắt buộc phải bóp ở đây chứ không phải bằng curl --limit-rate:' \
    '    # nếu chỉ giới hạn phía client thì server vẫn đẩy trọn 2MB vào buffer' \
    '    # ngay lập tức, client đọc dần từ buffer nên giết MASTER giữa chừng' \
    '    # cũng KHÔNG làm đứt được gì -> cảnh demo mất ý nghĩa.' \
    '    location /big.bin {' \
    '        limit_rate 100k;' \
    '    }' \
    '}' \
    > /etc/nginx/conf.d/default.conf

RUN printf '<h1>BACKEND: %s</h1>\n' "$WEB_NAME" > /usr/share/nginx/html/index.html

# File 2MB dùng cho cảnh "đứt phiên TCP": tải với --limit-rate 100k mất ~20 giây,
# đủ dài để failover xảy ra GIỮA CHỪNG một kết nối đang mở.
RUN head -c 2097152 /dev/urandom > /usr/share/nginx/html/big.bin

EXPOSE 80
