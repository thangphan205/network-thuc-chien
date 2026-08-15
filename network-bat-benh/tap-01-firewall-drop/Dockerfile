FROM nginx:alpine

# Cài đặt iptables và iproute2 để thao tác firewall và kiểm tra mạng
RUN apk add --no-cache iptables iproute2 iputils curl tcpdump

# Copy source HTML
COPY ./nginx/index.html /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
