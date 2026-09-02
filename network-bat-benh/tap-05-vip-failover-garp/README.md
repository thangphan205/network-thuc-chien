# 🩺 Ca Bệnh 05: Failover HA Thành Công Nhưng Dịch Vụ Vẫn Chết — Thủ Phạm Là Bảng ARP

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Cụm HA (Keepalived / VRRP / Pacemaker) vừa failover. Node MASTER chết, node BACKUP đã lên, đã cầm VIP, `nginx` vẫn chạy, cấu hình đúng 100%. **Nhưng client vẫn không truy cập được dịch vụ.** Ngồi chờ khoảng nửa phút thì tự sống lại — không ai chạm vào gì cả.
> * **Bản chất lỗi:** **Stale ARP Cache ở Tầng 2**. Client vẫn ôm địa chỉ MAC của node MASTER **đã tắt thở** cho IP của VIP. Node BACKUP cầm VIP rồi nhưng **không phát Gratuitous ARP (GARP)** để báo cho toàn LAN biết "VIP này giờ ứng với MAC của tôi" — nên không ai biết mà cập nhật.

> 📚 **Điều kiện tiên quyết:** Nắm được `ping`, `curl`, `ip neigh`, `tcpdump` ở mức cơ bản (xem series **Debug Mạng A-Z**). Đây là ca bệnh **Tầng 2** đầu tiên của series — mọi thứ ở L3/L4 đều đúng tuyệt đối, lỗi nằm dưới sâu hơn.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+---------------------------------------------------------------------------+
|                        DOCKER LAN (172.28.5.0/24)                         |
|                                                                           |
|                          VIP: 172.28.5.100                                |
|                    (địa chỉ mà client thực sự gọi)                        |
|                                                                           |
|   [Client 172.28.5.20]        [node-a .11 MASTER]     [node-b .12 BACKUP] |
|            │                    "TOI LA NODE A"        "TOI LA NODE B"    |
|            │                          │                        │          |
|   Bảng ARP nhớ:                       │                        │          |
|   VIP -> MAC của node-a ──────────────┘                        │          |
|                                     ☠️ CHẾT                     │          |
|            │                                                   │          |
|            │  Frame gửi tới MAC node-a (không còn tồn tại)      │          |
|            ▼                                                   │          |
|      [ VÀO HƯ VÔ ]                              VIP đã nhảy sang đây ─────┤
|      100% packet loss                           nhưng KHÔNG ai báo!       |
|                                                                           |
|   ────────────────────────────────────────────────────────────────────    |
|   💊 CHỮA: node-b phát Gratuitous ARP  ──>  cả LAN cập nhật MAC mới        |
|      (arping -U -c 3 -I eth0 172.28.5.100)   -> Thông ngay lập tức        |
+---------------------------------------------------------------------------+
```

> 🔑 Toàn bộ tập này gói gọn trong một câu: **IP đúng, route đúng, dịch vụ sống — nhưng khung tin Ethernet đang được gửi tới một địa chỉ MAC không còn tồn tại.**

---

## ❓ Vì Sao Node BACKUP Không Gửi GARP?

Câu hỏi đầu tiên ai cũng hỏi. Câu trả lời có ba tầng, và tầng nào cũng đáng biết.

### Tầng 1 — Trong lab: cố ý

`1-fault.sh` chỉ chạy đúng một dòng, không có `arping`:

```bash
docker compose exec node-b ip addr replace $VIP/24 dev eth0
```

Đó là bản mô phỏng script failover tự viết tay.

### Tầng 2 — Vì sao kernel không tự gửi giùm

Đo trong lab: bắt ARP đồng thời ở **cả client lẫn node-b**, rồi chạy `ip addr replace` trên node-b:

```
[client thấy]:  (KHÔNG CÓ GÓI ARP NÀO)
[node-b thấy]:  (KHÔNG CÓ GÓI ARP NÀO)
```

Gán IP xong, kernel **im re**. Ba lý do chồng lên nhau:

1. **Chuẩn ARP không có khái niệm "công bố".** RFC 826 định nghĩa ARP là giao thức **hỏi-đáp theo yêu cầu**: ai cần thì hỏi, ai giữ IP thì đáp. Không điều khoản nào bắt máy vừa nhận IP mới phải thông báo. Gratuitous ARP là **quy ước bổ sung** nghĩ ra sau, không phải nghĩa vụ của giao thức.

2. **Linux mặc định `arp_notify = 0`.** Tự kiểm: `sysctl -n net.ipv4.conf.eth0.arp_notify`.

3. **Bật `arp_notify=1` cũng KHÔNG cứu được ca này.** Kernel chỉ bắn GARP ở hai sự kiện: **device UP** và **NETDEV_NOTIFY_PEERS** (bonding failover, VM live migration). Thêm secondary IP lên interface **đang UP sẵn** không sinh event nào → vẫn không có gói nào. Đừng khuyên "bật `arp_notify` là xong" cho case VIP — nó không đúng.

> 🆚 **Đối chiếu IPv6 — chỗ này IPv4 thua rõ ràng.** NDP **bắt buộc** DAD (gửi Neighbor Solicitation khi nhận địa chỉ mới) và gửi **unsolicited Neighbor Advertisement**. IPv6 tự announce **theo chuẩn**, không cần công cụ ngoài. IPv4 phải gọi `arping` bằng tay.
>
> Nói cách khác: ca bệnh này về bản chất là **lỗ hổng thiết kế của ARP**, không phải lỗi ai đó đãng trí.

### Tầng 3 — Ngoài đời, dùng keepalived rồi vẫn mất GARP

Phần này mới là thứ bạn gặp trong production:

| # | Nguyên nhân | Ghi chú |
|---|---|---|
| **a** | **Script tự viết** — bash / Ansible / systemd `ExecStartPost` chỉ có `ip addr add` | Nguyên nhân số 1 |
| **b** | **Gói GARP mất thật** — broadcast không ACK, không retransmit; switch bận hoặc storm-control là bay | Chỉnh `garp_master_repeat`, `garp_master_refresh`, `garp_master_delay` |
| **c** | **GARP bắn quá sớm, cổng switch chưa forward** | Xem dưới — ca kinh điển nhất |
| **d** | **Pacemaker** — `ocf:heartbeat:IPaddr2` *có* gửi (`arp_count`, `arp_bg`), nhưng `IPaddr` bản cũ / RA custom thì không | Kiểm `pcs resource config` |
| **e** | **Container / VM / cloud** — VIP nằm trong netns không ra khỏi host; anti-spoofing hoặc MAC learning tắt ở hypervisor/VPC drop gói | |
| **f** | **Switch nuốt gói** — Dynamic ARP Inspection, port security, chống ARP spoofing trên firewall | |
| **g** | **Split-brain** — thừa GARP chứ không thiếu | Xem dưới |

**(c) Ca kinh điển — GARP bắn vào lúc STP chưa forward.**
Node lên MASTER ngay lúc boot hoặc link vừa up, GARP phóng ra khi cổng switch còn ở trạng thái **STP listening/learning** (tới 30 giây với STP truyền thống, nếu quên bật portfast / edge-port). Gói bắn vào hư không.

Nguy hiểm ở chỗ: **log phía server hoàn toàn sạch** — keepalived ghi rõ đã gửi GARP, `tcpdump` trên chính node đó cũng thấy gói đi ra. Nhưng không máy nào trong LAN nhận được. Muốn bắt được ca này **phải bắt gói ở máy thứ ba**, không phải ở node vừa failover.

**(g) Biến thể nguy hiểm hơn — split-brain.**
node-a chưa chết hẳn (chỉ đứt VRRP heartbeat), node-b vẫn lên MASTER. **Cả hai** cùng bắn GARP → bảng ARP toàn LAN **flapping** qua lại giữa hai MAC. Đây không phải "thiếu GARP" mà là "thừa GARP từ hai nguồn" — triệu chứng chập chờn, nặng và khó lần hơn nhiều so với ca bệnh trong lab này.

### 🔎 Verify trên hệ thống thật

Bắt gói ở **máy thứ ba** trong LAN (bắt trên node vừa failover là vô nghĩa — ở đó luôn thấy có gửi), rồi trigger failover:

```bash
# Lọc đúng Gratuitous ARP: Sender IP == Target IP (bắt cả dạng Request lẫn Reply)
tcpdump -i eth0 -n -e 'arp[14:4] = arp[24:4]'

# Chỉ muốn dạng Request (arping -U)? Thêm điều kiện opcode:
tcpdump -i eth0 -n -e 'arp[6:2] = 1 and arp[14:4] = arp[24:4]'
```

> ⚠️ Dùng bộ lọc **rộng** (không kèm opcode) khi đi soi hệ thống lạ. `arping -A` phát GARP dạng **Reply** (opcode 2) — thêm `arp[6:2] = 1` là lọc mất luôn, rồi kết luận nhầm "không có GARP nào".
>
> Wireshark có sẵn tương đương: `arp.isgratuitous == 1`.

Kiểm cấu hình:
```bash
grep -iE 'garp|vmac' /etc/keepalived/keepalived.conf    # keepalived
pcs resource config <ten-vip> | grep -i arp             # pacemaker
grep -rn 'ip addr add' /etc/systemd/ /usr/local/bin/    # script tự viết -> thủ phạm
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-05-vip-failover-garp
docker compose up -d --build
```

---

### Bước 2: Dựng trạng thái BÌNH THƯỜNG (bắt buộc — đây là "ảnh chụp trước khi bệnh")

```bash
./scripts/0-setup.sh
```

Script gán VIP `172.28.5.100` cho **node-a**, rồi cho client gọi VIP một lần để học MAC vào bảng ARP:

```
<h1>TOI LA NODE A (MASTER)</h1>
172.28.5.100 dev eth0 lladdr e6:78:aa:e9:8b:35 REACHABLE
```

> 💡 Chạy lại `./scripts/0-setup.sh` bất cứ lúc nào để **reset sạch lab** về trạng thái này.
> ⚠️ MAC trong lab là **ngẫu nhiên theo từng lần chạy** — đừng so với MAC trong README, hãy so với MAC mà `./scripts/test.sh` in ra trên máy bạn.

---

### Bước 3: Kích hoạt Ca Bệnh & Bắt mạch

1. Failover: MASTER chết, BACKUP cướp VIP nhưng **quên phát GARP**:
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chẩn đoán:
   ```bash
   ./scripts/test.sh
   ```

#### 🔍 Hiện tượng quan sát được:
```
🩺 [BƯỚC 1] MAC THỰC TẾ của 2 node:
node-a (MASTER):  (node-a đang CHẾT — đúng kịch bản failover)
node-b (BACKUP):  ether 52:9a:0e:2c:44:ba
VIP 172.28.5.100 hiện nằm trên: node-b

🩺 [BƯỚC 2] Bảng ARP trên Client:
172.28.5.100 dev eth0 lladdr e6:78:aa:e9:8b:35 REACHABLE     ← MAC của thằng ĐÃ CHẾT

🩺 [BƯỚC 3] Ping VIP:
3 packets transmitted, 0 received, 100% packet loss

🩺 [BƯỚC 4] curl VIP:
❌ Không gọi được dịch vụ qua VIP — dù backup đã lên và nginx vẫn chạy!
```

> 💡 BƯỚC 2 in **cả bảng ARP**, không lọc. Sau `0-setup.sh` bảng thường chỉ có đúng dòng VIP; nếu bạn đã ping/curl thẳng vào `.11`/`.12` trước đó thì sẽ thấy thêm vài dòng nữa — chỉ cần đọc đúng dòng `172.28.5.100`.

👉 **Đọc kỹ BƯỚC 2:** MAC mà client đang ôm **không khớp với bất kỳ máy nào còn sống**. Nó là MAC của node-a — máy đã tắt. Trạng thái vẫn ghi `REACHABLE` một cách đầy tự tin, vì Linux chưa có lý do gì để nghi ngờ.

---

### Bước 4: Bắt mạch trên Wireshark

1. Bắt gói tin **trong container `client`** rồi mở bằng Wireshark (xem mục [🦈 Bắt gói tin bằng Wireshark](../README.md#-bắt-gói-tin-bằng-wireshark-trên-mọi-hệ-điều-hành) ở README series):
   ```bash
   docker compose exec -d client tcpdump -i eth0 -w /tmp/lab05.pcap -n -e "arp or icmp"
   docker compose exec client ping -c 3 -W 1 172.28.5.100
   ./scripts/2-fix.sh                      # phát GARP để bắt luôn gói GARP vào pcap
   docker compose exec client pkill tcpdump
   docker compose cp client:/tmp/lab05.pcap ./lab05.pcap
   ```

2. Display filter:
   ```wireshark
   arp || icmp
   ```

3. Soi gói tin — **lúc đang bệnh**:
   ```
   a6:51:24:98:6b:ed > 32:d2:7c:6a:2e:36, IPv4, 172.28.5.20 > 172.28.5.100: ICMP echo request
   a6:51:24:98:6b:ed > 32:d2:7c:6a:2e:36, IPv4, 172.28.5.20 > 172.28.5.100: ICMP echo request
   ```
   * Địa chỉ IP đích **hoàn toàn đúng** (`172.28.5.100`).
   * Destination MAC là MAC của node-a — máy đã chết. Frame đi vào hư vô.
   * **Không có một gói ARP nào.** Client không hề hỏi lại "ai đang giữ VIP?" — vì entry còn `REACHABLE`, nó tin chắc mình đã biết câu trả lời. Chính sự **im lặng** này là chẩn đoán.
   * **Không có gói reply nào.**

4. Soi gói tin — **khoảnh khắc GARP được phát ra**:
   ```
   52:9a:0e:2c:44:ba > ff:ff:ff:ff:ff:ff, ARP, Request who-has 172.28.5.100 tell 172.28.5.100
   ```
   👉 Đây là dấu vân tay của **Gratuitous ARP**: gói ARP Request gửi **broadcast**, trong đó **Sender IP = Target IP = chính VIP**. Nó không hỏi ai cả — nó đang **tuyên bố**. Wireshark có sẵn filter riêng:
   ```wireshark
   arp.isgratuitous == 1
   ```

> 🔧 **Vì sao mỗi gói hiện 2 lần?** Chỉ những khung tin **client GỬI ĐI** mà bridge phải flood (broadcast, hoặc unicast tới MAC không còn trong bảng chuyển mạch) mới bị ghi 2 lần. Đo thực tế trong lab:
>
> | Khung tin | Số lần hiện |
> |---|---|
> | Client **gửi** broadcast (ARP request) | 2 lần |
> | Client **gửi** unicast tới MAC đã chết | 2 lần |
> | Client **gửi** unicast tới MAC còn sống | 1 lần |
> | Client **nhận** (GARP, ICMP reply) | 1 lần |
>
> Vì vậy ICMP echo request ở trên hiện 2 lần, còn gói GARP nhận từ node-b ở dưới chỉ hiện 1 lần. Không phải lỗi — nhưng cần biết trước để khỏi đọc nhầm.

---

### Bước 5: Khắc Phục Sự Cố (Fix & Remediate)

```bash
./scripts/2-fix.sh
```

Script chỉ làm **đúng một việc, ở đúng nơi phải làm** — trên node-b:
```bash
arping -U -c 3 -I eth0 172.28.5.100
```

Kết quả — **không hề chạm một ngón tay nào vào client**:
```
✅ Đã phát GARP! Bảng ARP của client:
172.28.5.100 dev eth0 lladdr 52:9a:0e:2c:44:ba STALE      ← client TỰ cập nhật sang MAC node-b
```

Kiểm tra lại:
```bash
./scripts/test.sh
```
```
🩺 [BƯỚC 3] Ping VIP:  3 packets transmitted, 3 received, 0% packet loss
🩺 [BƯỚC 4] curl VIP:  <h1>TOI LA NODE B (BACKUP)</h1>
```

👉 `curl` giờ trả về **NODE B**. Failover thật sự hoàn tất — không phải "hoàn tất trên giấy".

> 🔑 **Đây mới là bài học lớn nhất của tập:** cách chữa nằm ở **phía server vừa failover**, không phải phía client. Sai lầm kinh điển là cử admin chạy quanh `ip neigh flush` từng máy client — vừa không khả thi với hàng trăm máy, vừa chữa triệu chứng thay vì căn nguyên.

---

### Bước 6: Cảnh Kết — Thử KHÔNG chữa gì cả

Reset rồi gây lỗi lại, nhưng lần này **ngồi im**:

```bash
./scripts/0-setup.sh && ./scripts/1-fault.sh
./scripts/3-tu-khoi.sh
```

```
⏱️  Không chữa gì cả. Chỉ ping mỗi giây và đếm xem bao giờ tự sống lại...
💡 TỰ KHỎI sau ~50 giây — không ai chạm vào gì cả.
```

Linux tự khỏi sau khoảng **30–50 giây** trong lab này: entry `REACHABLE` hết hạn → `STALE` → `DELAY` → thăm dò unicast tới MAC cũ (thất bại) → cuối cùng broadcast ARP hỏi lại → học đúng MAC mới. Bạn xem được từng bước bằng cách chạy song song `docker compose exec client ip neigh show 172.28.5.100`.

> ⚠️ **Con số của bạn sẽ KHÁC — và đó là đúng.** Kernel lấy `base_reachable_time_ms` (mặc định 30000) rồi **random hoá trong khoảng 0.5–1.5 lần** cho từng entry, tức 15–45 giây, mới đến lượt các bước thăm dò phía sau. Chạy nhiều lần trong lab này ra khoảng 40–55 giây. Đừng chờ ra đúng một con số cố định.

Đó cũng chính là lời giải cho câu "**chờ một lúc là tự vào được**" và "**reboot máy client thì hết**" mà người dùng hay báo.

> ⚠️ **Ngoài đời còn tệ hơn nhiều.** 30–50 giây là con số của Linux trong lab. Máy Windows, router, thiết bị IoT/máy in đời cũ có thể ôm ARP entry sai **hàng phút**. Nhân con số đó với mỗi lần failover, đó là SLA của bạn.

> 🧩 **Phân biệt hai cái bảng — đây là tập Tầng 2, đừng gộp chúng làm một:**
>
> | | Nằm ở đâu | Ánh xạ | Hỏng thì sao |
> |---|---|---|---|
> | **Bảng ARP** | Trên **host** (client, router) | IP → MAC | Gửi frame tới MAC không tồn tại — **đúng ca bệnh này** |
> | **Bảng CAM/MAC** | Trên **switch** | MAC → cổng | Switch flood ra mọi cổng, chậm & lộ traffic |
>
> Một gói GARP broadcast làm mới **cả hai cùng lúc**: host cập nhật IP→MAC, switch học lại MAC nằm ở cổng nào. Đó là lý do một lệnh `arping` ở node-b sửa được cả LAN.

---

## 🧠 Bác Sĩ Mạng Đúc Kết

1. **GARP là trách nhiệm của bên failover, không phải bên client.**
   Khi một máy nhận VIP mới, thay card mạng, hoặc lên làm MASTER, nó **PHẢI** chủ động broadcast Gratuitous ARP:
   ```bash
   arping -U -c 3 -I eth0 <VIP>      # -U = Unsolicited (thông báo, không phải hỏi)
   arping -A -c 3 -I eth0 <VIP>      # -A = gửi dạng ARP Reply, một số thiết bị chỉ nghe kiểu này
   ```
   Gửi **nhiều gói** (3–5): ARP chạy **thẳng trên Ethernet** (ethertype `0x0806`) — không có IP, không có UDP, **không ACK, không retransmit**. Mất là mất luôn, không ai báo.

2. **Keepalived / VRRP / Pacemaker đã làm sẵn việc này.** Rủi ro nằm ở **script failover tự viết tay** — kiểu `ip addr add VIP` rồi xong. Nếu bạn đang tự động hoá failover bằng bash/Ansible, hãy kiểm tra ngay xem có dòng `arping` không.

3. **"Sao cụm HA chỗ tôi chưa bao giờ dính lỗi này?" — vì MAC ảo.**
   Chuẩn VRRP (RFC 5798) quy định router ảo dùng **MAC ảo** `00:00:5e:00:01:<VRID>`. MAC đó **nhảy theo VIP** sang node mới, nên bảng ARP của client vẫn đúng nguyên — không cần GARP, không có ca bệnh này.
   * Thiết bị phần cứng (Cisco/Juniper HSRP/VRRP) mặc định làm vậy.
   * **Keepalived trên Linux thì KHÔNG** — mặc định `use_vmac` tắt, nó chỉ `ip addr add` VIP lên NIC thật, MAC vẫn là MAC của NIC đó. Failover = **đổi MAC**, và nó dựa hoàn toàn vào GARP để báo cho LAN.

   👉 Lab này mô phỏng đúng case keepalived mặc định — cũng là case phổ biến nhất trên Linux.

4. **Trên cloud, cách chữa này KHÔNG chạy.** VPC của AWS/Azure/GCP không flood Tầng 2 — GARP bắn ra không ai nghe. VIP + `arping` sẽ **không** failover được. Ở đó phải:
   * gọi API dời secondary private IP / gắn lại ENI, hoặc
   * sửa route table trỏ sang instance mới, hoặc
   * dùng thẳng Load Balancer / health check của nhà cung cấp.

   Đây là bài học dễ bị áp dụng sai nhất: đúng tuyệt đối trong DC/on-prem, vô nghĩa trên cloud.

5. **GARP chỉ CẬP NHẬT entry có sẵn, không TẠO entry mới.** Linux mặc định `net.ipv4.conf.*.arp_accept = 0`. Verify trong lab: xoá sạch bảng ARP của client rồi bắn `arping -U` từ node-b → client **không** tạo entry nào.
   * Không phải lỗi — đó là nhóm máy **đang nói chuyện với VIP** mới cần chữa, và đúng nhóm đó được chữa.
   * Máy có cache nguội thì cứ ARP bình thường, ra MAC đúng ngay.
   * Cũng là lý do GARP không biến mạng thành thiên đường ARP spoofing.

6. **Có gửi GARP mà VẪN chết?** Kiểm tra thứ đang nuốt gói: Dynamic ARP Inspection (DAI), port security trên switch, tính năng chống ARP spoofing trên firewall, hoặc Wi-Fi AP làm proxy ARP. Bắt `tcpdump` **ở phía client**, không phải ở node vừa failover — để biết gói có thật sự tới nơi không.

7. **Đọc bảng ARP cho đúng:**
   ```bash
   ip neigh show                 # xem toàn bộ bảng
   ip neigh show 172.28.5.100    # xem 1 IP
   ```
   Các trạng thái cần biết: `REACHABLE` (tin tưởng tuyệt đối — và đó là lúc nguy hiểm nhất), `STALE` (nghi ngờ, sẽ xác minh khi cần), `PERMANENT` (đóng đinh vĩnh viễn, không bao giờ tự hết hạn).

8. **Xoá cache ARP thủ công (chỉ khi chữa cháy):**
   ```bash
   ip neigh del 172.28.5.100 dev eth0      # xoá 1 IP
   ip neigh flush dev eth0                 # xoá cache động của cả interface
   ip neigh flush dev eth0 nud permanent   # ⚠️ BẮT BUỘC có `nud permanent` mới xoá được entry tĩnh
   ```
   > 🪤 **Bẫy thường gặp:** `ip neigh flush dev eth0` **KHÔNG** xoá được entry `PERMANENT`. Nhiều người gõ lệnh này, thấy không có lỗi báo về, rồi tưởng đã sạch — trong khi entry sai vẫn nằm nguyên đó.

9. **Giám sát:** cảnh báo khi VIP đổi chủ mà không thấy GARP trên LAN. Rẻ hơn nhiều so với việc dò tìm lúc 2 giờ sáng.

---

## 🍚 Cơm Thêm: Nếu Client và Server KHÁC Subnet?

Lab trên đặt client và server cùng một subnet. Đời thật hiếm khi vậy — thường có router hoặc L3 switch đứng giữa. Lúc đó client **không bao giờ ARP hỏi VIP**, nên triệu chứng "client ôm MAC của node đã chết" **biến mất thật**.

Hết bệnh chưa? **Chưa.** Bệnh đổi chỗ sang **router**, và đổi theo hướng tệ hơn: client sạch trơn không manh mối, đứt một chiều, và **mất luôn cơ chế tự khỏi sau 30 giây** (Cisco IOS ôm entry sai mặc định **4 tiếng**).

👉 Xem [**com-them.md**](com-them.md) — có lab riêng chạy được ở `com-them-router/`:

```bash
cd com-them-router
docker compose up -d --build
./scripts/0-setup.sh && ./scripts/1-fault.sh && ./scripts/test.sh
```

---

## 📝 Câu Hỏi Ôn Tập

1. Node BACKUP đã cầm VIP, dịch vụ vẫn chạy, IP/subnet/route đều đúng. Vậy gói tin của client **chết ở đâu**, và **vì sao**?
2. Nhìn vào Wireshark, làm sao phân biệt một gói **Gratuitous ARP** với một gói ARP Request bình thường?
3. Vì sao cách chữa đúng là chạy `arping` trên **node-b**, chứ không phải `ip neigh flush` trên từng client?
4. Vì sao chờ khoảng nửa phút thì hệ thống **tự khỏi**? Điều đó nói lên gì về mức độ nguy hiểm của lỗi này trong sản xuất?
5. Cụm HA chạy trên router Cisco dùng VRRP chuẩn **không bao giờ** dính ca bệnh này, còn keepalived trên Linux thì có. Khác nhau ở đâu?
6. Bạn bê nguyên mô hình VIP + `arping` này lên một VPC của AWS. Chuyện gì xảy ra, và vì sao?

<details><summary>Gợi ý đáp án</summary>

1. Chết ở **Tầng 2**. Bảng ARP của client vẫn map VIP → MAC của node-a đã tắt, nên khung Ethernet mang Destination MAC không còn tồn tại trên mạng. Gói đi vào hư vô — không ai nhận, không ai báo lỗi. Mọi thứ từ L3 trở lên đều đúng, nên `ping`/`traceroute`/route table đều "sạch", càng khó nghi ngờ.
2. Dấu hiệu duy nhất cần nhớ: **broadcast** + **Sender IP = Target IP** (máy "hỏi" về chính địa chỉ của nó). Nó không hỏi, nó tuyên bố. Có **hai dạng** đều hợp lệ: ARP **Request** (`arping -U`) và ARP **Reply** (`arping -A`) — đừng lọc theo opcode kẻo sót dạng Reply. Wireshark: `arp.isgratuitous == 1`.
3. Vì căn nguyên nằm ở **bên vừa đổi MAC**, không phải bên client. Một lệnh `arping` trên node-b sửa cho **toàn bộ LAN cùng lúc** — kể cả switch, router, máy in, thiết bị bạn không SSH vào được. `ip neigh flush` từng client là chữa triệu chứng và bất khả thi ở quy mô thật.
4. Vì entry `REACHABLE` hết hạn (kernel random hoá 15–45s quanh `base_reachable_time_ms`) → chuyển `STALE` → `DELAY` (5s) → `PROBE` (3 lần thăm dò unicast tới MAC cũ, thất bại) → `FAILED` → broadcast ARP → học lại đúng MAC. Tổng cộng ~30–50s. Nguy hiểm ở chỗ nó **tự khỏi**: lúc kỹ sư kịp SSH vào kiểm tra thì mọi thứ đã bình thường, không log nào ghi lại, nên lỗi bị xếp vào "chập chờn không rõ nguyên nhân" và **lặp lại ở mỗi lần failover**.
5. VRRP chuẩn (RFC 5798) dùng **MAC ảo** `00:00:5e:00:01:<VRID>` — MAC nhảy sang node mới cùng với VIP, nên bảng ARP của client vẫn đúng, không cần thông báo lại. Keepalived trên Linux mặc định **không** dùng MAC ảo (`use_vmac` tắt): nó chỉ gán VIP lên NIC thật, nên failover **làm đổi MAC** và bắt buộc phải có GARP.
6. **Không failover được.** VPC của AWS/Azure/GCP không phải mạng Tầng 2 thật — nó không flood broadcast/unknown-unicast giữa các instance, nên GARP bắn ra không ai nghe, và bản thân IP cũng bị ràng vào ENI. Trên cloud phải dời IP/ENI bằng **API**, sửa route table, hoặc dùng Load Balancer của nhà cung cấp.
</details>

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
