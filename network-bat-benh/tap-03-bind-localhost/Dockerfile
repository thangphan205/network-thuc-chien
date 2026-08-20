FROM nginx:alpine

# Cài iproute2 để có lệnh `ss` (nginx:alpine chỉ có netstat của busybox),
# tcpdump để bắt gói ngay trên server phục vụ bài giảng
RUN apk add --no-cache iproute2 iputils curl tcpdump

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
