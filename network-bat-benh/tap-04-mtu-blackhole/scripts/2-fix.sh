#!/usr/bin/env bash
# Chữa bệnh: Kẹp MTU của route — giữ nguyên "đường ống nghẽn" nhưng ép Server
# chỉ gửi các segment nhỏ để không bao giờ chạm ngưỡng bị DROP.
set -e
echo "🩺 Đang khắc phục sự cố (Fixing): Kẹp MTU route tới client — KHÔNG gỡ luật chặn gói lớn..."

# Bài học thực tế: nhiều khi KHÔNG sửa được đường truyền nghẽn (VPN/tunnel/cloud của bên thứ 3).
# Server là ENDPOINT nên không dùng được `iptables ... TCPMSS --clamp-mss-to-pmtu`
# (luật đó chạy ở chain FORWARD, tức trên router trung gian). Cách tương đương ở endpoint
# là kẹp MTU của route: Server tự tính MSS gửi đi = MTU - 40 = 900 bytes,
# nên mọi segment server->client tối đa ~940 bytes < ngưỡng 1000 bytes bị chặn ở 1-fault.sh.
docker compose exec web-server ip route replace 172.28.4.20/32 dev eth0 mtu 940

echo "✅ Đã kẹp route MTU 940 → MSS 900!"
echo "👉 Luật chặn gói >1000 bytes VẪN còn, nhưng Server nay chỉ gửi segment nhỏ nên Web tải trọn vẹn."
echo "ℹ️  Lưu ý: ping -s 1400 -M do VẪN rớt 100% sau khi chữa — đúng như vậy. Ta né đường ống nghẽn chứ không sửa nó."
echo "ℹ️  Muốn khôi phục hoàn toàn (gỡ cả luật chặn): docker compose exec client iptables -F"
