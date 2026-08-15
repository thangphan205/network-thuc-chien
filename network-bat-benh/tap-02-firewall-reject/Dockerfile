FROM nginx:alpine
RUN apk add --no-cache iptables iproute2 iputils curl tcpdump
COPY ./nginx/index.html /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
