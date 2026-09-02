FROM nginx:alpine
ARG NODE_NAME=node
ARG NODE_IP=0.0.0.0
# iputils cung cấp `arping` — công cụ phát Gratuitous ARP khi failover
RUN apk add --no-cache iproute2 iputils curl tcpdump
RUN printf '<h1>TOI LA %s</h1><p>IP that cua may nay: %s</p>\n' "$NODE_NAME" "$NODE_IP" \
      > /usr/share/nginx/html/index.html
EXPOSE 80
