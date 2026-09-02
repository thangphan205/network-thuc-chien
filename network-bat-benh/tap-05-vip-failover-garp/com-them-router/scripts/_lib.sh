# Hằng số & tiện ích dùng chung cho lab "Cơm Thêm — có Router ở giữa"
VIP=172.28.7.100
CLIENT_NET=172.28.6.0/24
SERVER_NET=172.28.7.0/24
R_CLIENT=172.28.6.254      # chân router phía subnet CLIENT
R_SERVER=172.28.7.254      # chân router phía subnet SERVER

# Docker không đảm bảo interface nào là eth0/eth1 khi container gắn 2 mạng,
# nên phải dò tên interface theo IP thay vì hardcode.
r_srv_if() {
  docker compose exec -T router ip -o -4 addr show \
    | awk '$4 ~ /^172\.28\.7\./ {print $2; exit}' | tr -d '\r'
}
