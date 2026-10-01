FROM nginx:alpine
RUN apk add --no-cache socat tcpdump
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh
COPY nginx/conf/dai.conf /etc/nginx/conf.d/dai.conf.bak
COPY nginx/conf/ngan.conf /etc/nginx/conf.d/ngan.conf.bak
COPY nginx/conf/dai.conf /etc/nginx/conf.d/default.conf
ENTRYPOINT ["/entrypoint.sh"]
