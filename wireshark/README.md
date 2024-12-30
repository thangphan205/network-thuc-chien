# 1. Slide trình bày ở series Wireshark

[Google Drive](https://docs.google.com/presentation/d/18q6NKZPcmijGf4xYvZo-jPOLNpGaCrBgDNEAkpFDCxw/edit?usp=sharing)

# 2. Các hình vẽ ở draw.io

[Google Drive](https://drive.google.com/file/d/1tSbA7Y6WHOYy8_vyWvnbrE-AZNuhOfOv/view?usp=sharing)

# 3. Tài liệu ở các video

## GeoIP Maxmind Database

| Database    | Download |
| -------- | ------- |
| Country | <https://share.9ping.cloud/wireshark/GeoLite2-Country.mmdb> |
|City| <https://share.9ping.cloud/wireshark/GeoLite2-City.mmdb>|
|ASN| <https://share.9ping.cloud/wireshark/GeoLite2-ASN.mmdb>|

## tcpdump

| Command    | Explanation |
|---|---|
| -i INTERFACE | capture traffic trên 1 interface, nếu capture tất cả interface thì gõ "-i any"|
| -nn | không phân giải ngược IP và port number thành domain/service name |
| -vv | hiển thị nhiều thông tin verbose |
| host IP_ADDRESS | ví dụ "host 192.168.1.1" chỉ capture traffic có source IP hoặc Dest IP là 192.168.1.1 |
| net NETWORK | ví dụ "net 192.168.1.0/24" chỉ capture traffic có source IP hoặc Dest IP trong subnet 192.168.1.0/24 |
| port 80 | ví dụ "port 80" chỉ capture traffic có source port hoặc Dest port là 80|
| -e | include MAC address|
| -r | đọc file capture|
| arp, ether, icmp, ip, ip6, tcp | các protocol thường sử dụng, chỉ cần gõ protocol muốn filter  |
| and, not, or | các điều kiện lọc |
| gt, lt, ge, le | greater than (lớn hơn), less than (nhỏ hơn), greater than or equal (lớn hơn hoặc bằng), less than or equal (nhỏ hơn hoặc bằng)|

tcpflags:
tcp-syn TCP SYN (Synchronize)
tcp-ack TCP ACK (Acknowledge)
tcp-fin TCP FIN (Finish)
tcp-rst TCP RST (Reset)
tcp-push TCP Push

```bash
tcpdump "tcp[tcpflags] == tcp-syn" : chỉ bắt gói tin TCP SYN
tcpdump "tcp[tcpflags] & tcp-syn != 0": bắt gói tin TCP có cờ SYN bật
tcpdump "tcp[tcpflags] & (tcp-syn|tcp-ack) != 0" : bắt gói tin TCP có cờ SYN bật hoặc cờ ACK bật
```

## Tshark
