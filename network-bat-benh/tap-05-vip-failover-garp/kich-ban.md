# 🎬 Tập 05 — 12 Kịch Bản Thực Hành

> Tài liệu này là phần thực hành chi tiết. Phần lý thuyết (vì sao BACKUP không
> gửi GARP, triệu chứng đổi thế nào khi có router) nằm ở [README.md](./README.md).

**Quy tắc bất di bất dịch: sau MỖI kịch bản, chạy `./scripts/0-setup.sh`.**
Nó dọn sạch mọi dấu vết (rule iptables, cờ `nopreempt`/`USE_VMAC`, ARP kiểu
Cisco, HAProxy bị giết, VIP gán tay, route bay mất sau restart) rồi dựng lại
trạng thái chuẩn.

Ba terminal nên mở sẵn suốt buổi:

```bash
# Terminal 1 — chạy kịch bản
./scripts/0-setup.sh

# Terminal 2 — máy đo phía client (nạn nhân)
docker exec -it lab05-client-remote monitor.sh

# Terminal 3 — soi bảng ARP của router (ổ bệnh thật)
./scripts/xem-arp-router.sh
```

> ⚠️ **MAC trong lab ngẫu nhiên theo từng lần chạy.** Đừng so với MAC trong tài
> liệu này — hãy so với MAC mà `./scripts/test.sh` in ra trên máy bạn. Các con số
> thời gian cũng sẽ lệch chút ít; hãy kiểm **dấu hiệu**, đừng kiểm con số.

---

## Bản đồ 12 kịch bản

| Nhóm | KB | Script | Câu chuyện |
| :--- | :-- | :--- | :--- |
| **A. Failover chạy đúng** | 1 | `1-failover-chuan.sh` | Keepalived làm tròn việc — mốc so sánh |
| | 2 | `2-dut-phien-tcp.sh` | Nhưng phiên TCP đang mở vẫn đứt |
| **B. Ổ bệnh Tầng 2** | 3 | `3-fault.sh` | Script tự chế cướp VIP, quên GARP |
| | 4 | `4-fix.sh` | Chữa đúng: 5 gói ARP bắn từ phía server |
| | 5 | `5-tu-khoi.sh` | Linux tự khỏi 32s — Cisco thì 4 tiếng |
| | 6 | `6-chua-tren-router.sh` | Chữa cháy phía router khi không với được server |
| | 7 | `7-garp-khong-xuyen-router.sh` | GARP dừng ở biên L3 — bắn thêm cũng vô ích |
| **C. Cụm HA tự đánh nhau** | 8 | `8-split-brain.sh` | Thừa GARP: hai node cùng giữ VIP |
| | 9 | `9-preempt.sh` | Một sự cố, hai lần mất phiên |
| **D. Chết vì lý do KHÁC L2** | 10 | `10-dich-vu-chet.sh` | Dịch vụ chết nhưng máy vẫn sống |
| | 11 | `11-backend-qua-router.sh` | Mất backend sau router → HTTP 503 |
| | 12 | `12-use-vmac.sh` | Chữa tận gốc: MAC ảo không bao giờ đổi |

---

# NHÓM A — Failover Chạy Đúng

Trước khi xem bệnh, phải biết thế nào là khoẻ. Hai kịch bản này là mốc so sánh
cho tất cả những gì đến sau.

## KB1 — Failover đúng chuẩn

**Tình huống ngoài đời.** Node MASTER chết đột ngột (mất điện, kernel panic,
người ta rút nhầm dây). Keepalived làm đúng mọi thứ. Bạn cần biết con số
downtime "tốt nhất có thể" là bao nhiêu để sau này còn so sánh.

**Chạy:**
```bash
./scripts/1-failover-chuan.sh
```

**Thấy gì:**
```
   router(.52):   c2:df:af:34:8a:99    -> node-a
   client-lan:    c2:df:af:34:8a:99    -> node-a

💥 SIGKILL node-a (MASTER) — chết đột ngột, không kịp nhường quyền...

VIP giờ nằm trên: node-b
   client-lan:      DOWNTIME ≈ 2.8 giây (mất 14 gói liên tiếp)
   client-remote:   DOWNTIME ≈ 2.8 giây (mất 14 gói liên tiếp)

   router(.52):   62:15:47:b1:04:8d    -> node-b
   client-lan:    62:15:47:b1:04:8d    -> node-b
```

**Vì sao ~2.8 giây.** Đó là ≈ 3 × `advert_int`. VRRP phải bỏ lỡ 3 lần
advertisement liên tiếp mới dám kết luận MASTER đã chết. **Con số này KHÔNG
liên quan gì tới ARP** — ARP được sửa gần như tức thì nhờ GARP.

**Vì sao hai client bằng nhau.** GARP là broadcast trong subnet của VIP. Router
có một chân nằm trong subnet đó, nên nó nhận GARP y hệt `client-lan`. Router
cập nhật xong thì `client-remote` được cứu theo, dù bản thân nó không nghe thấy
gói nào.

**Gặp ở đâu.** Đây là hành vi bình thường của mọi cụm keepalived cấu hình đúng.
Muốn giảm 2.8 giây thì hạ `advert_int` (ví dụ `0.5`), đổi lại tốn thêm băng
thông multicast và nhạy hơn với mất gói.

---

## KB2 — GARP cứu gói tin, không cứu phiên TCP

**Tình huống ngoài đời.** Sếp đọc báo cáo "downtime 3 giây" và yên tâm. Nhưng
support vẫn nhận khiếu nại: upload file thất bại, truy vấn báo cáo đứt giữa
chừng, WebSocket rớt — đúng vào lúc failover.

**Chạy:**
```bash
./scripts/2-dut-phien-tcp.sh
```

**Thấy gì:**
```
Kết nối TCP đang tải dở:
   http=200 tai_ve=614400/2097152 bytes thoi_gian=5.257870s curl_exit=18

Còn một request MỚI thì sao?
   HTTP/1.1 200 OK
   x-lb-node: node-b
```

**Vì sao.** Một kết nối TCP gắn chặt vào một máy cụ thể: số seq/ack, cửa sổ,
buffer, trạng thái TLS. `node-b` là máy KHÁC, HAProxy trên đó là tiến trình
KHÁC, hoàn toàn không biết gì về phiên đang chạy dở. GARP chỉ sửa được Tầng 2 —
"gửi frame tới đúng MAC". Không giao thức nào chuyển được một phiên TCP đang
chạy sang máy khác.

**Chữa.** Không có cách nào chữa triệt để ở tầng hạ tầng. Ba hướng:
- `conntrackd` — đồng bộ bảng conntrack giữa 2 node (dùng cho firewall/NAT)
- session replication ở tầng ứng dụng (Redis dùng chung, sticky + failover)
- **Chấp nhận và thiết kế client có retry** — hướng thực tế nhất

**Gặp ở đâu.** Mọi lần failover, không trừ trường hợp nào. Đây là lý do "HA" và
"zero downtime" là hai thứ khác nhau.

> 🪤 **Bẫy khi tự dựng lại lab này.** Phải bóp băng thông ở **phía nginx**
> (`limit_rate 100k`), KHÔNG dùng `curl --limit-rate`. Giới hạn phía client chỉ
> làm curl đọc chậm khỏi buffer, còn server đã đẩy hết 2MB đi rồi — giết MASTER
> lúc đó cũng không đứt được gì và cả kịch bản mất ý nghĩa.

---

# NHÓM B — Ổ Bệnh Tầng 2

Đây là ruột của tập. Năm kịch bản đi từ gây bệnh, chữa đúng, đo tự khỏi, chữa
cháy, tới hiểu vì sao cách chữa lại hoạt động.

## KB3 — Ca bệnh: script tự chế quên GARP

**Tình huống ngoài đời.** Cụm HA không dùng keepalived mà dùng script bash /
Ansible / systemd `ExecStartPost` tự viết. Script gán VIP đúng, dịch vụ lên
đúng, mà client vẫn chết.

**Chạy:**
```bash
./scripts/3-fault.sh
./scripts/test.sh      # chẩn đoán đầy đủ 8 bước
```

**Thấy gì:**
```
VIP 172.28.52.100 hiện nằm trên: node-b   ← ĐÚNG chỗ
   be_web   web-1    UP
   be_web   web-2    UP
   ← Backend UP hết. Dịch vụ sống 100%.

   router(.52):   7a:cc:8a:25:ca:23    -> node-a ĐÃ CHẾT
   client-lan:    7a:cc:8a:25:ca:23    -> node-a ĐÃ CHẾT

   client-remote:
      172.28.51.254 dev eth0 lladdr e6:80:aa:95:23:18 REACHABLE
      ↑ KHÔNG có dòng nào cho 172.28.52.100

   lab05-client-lan         http_code=000  curl_exit=28 ← TIMEOUT
   lab05-client-remote      http_code=000  curl_exit=28 ← TIMEOUT
```

**Vì sao Keepalived phải bị giết trước.** Keepalived **không bao giờ** quên phát
GARP — không có tuỳ chọn nào tắt được. Đặt cả nhóm `garp_master_*` về `0` thì số
gói giảm từ 5 xuống 1, nhưng **không về 0**. Nên muốn dựng lại ca bệnh, script
buộc phải giết keepalived rồi cướp VIP bằng đúng một dòng:

```bash
docker exec lab05-node-b ip addr replace 172.28.52.100/24 dev eth0
```

👉 **Kết luận mạnh nhất của cả tập: ca bệnh này chỉ tồn tại khi bạn KHÔNG dùng
Keepalived.**

**Ba chỗ để soi, theo đúng thứ tự:**

| Soi ở đâu | Thấy gì | Kết luận |
| :--- | :--- | :--- |
| `client-remote` | bảng ARP **sạch tinh** | ngõ cụt — đừng phí thời gian ở đây |
| **router chân `.52`** | MAC của máy **đã chết** | ✅ **ổ bệnh** |
| `client-lan` | MAC của máy **đã chết** | ổ bệnh thứ hai, độc lập |

**Gặp ở đâu.** Nguyên nhân số 1 ngoài production. Lệnh đi tìm thủ phạm:
```bash
grep -rn 'ip addr add' /etc/systemd/ /usr/local/bin/ /etc/ansible/
```

---

## KB4 — Chữa đúng: 5 gói ARP bắn từ phía server

**Tình huống ngoài đời.** Bạn đã xác định được ổ bệnh. Giờ cần một lệnh chạy
được ngay, không cần quyền vào router, không cần đụng vào client nào.

**Chạy:**
```bash
./scripts/4-fix.sh
```

**Thấy gì:**
```
📋 TRƯỚC KHI CHỮA:
   router(.52):   d2:57:56:70:7f:e2    -> node-a ĐÃ CHẾT
   client-lan:    d2:57:56:70:7f:e2    -> node-a ĐÃ CHẾT

💊 docker exec lab05-node-b arping -U -c 5 -I eth0 172.28.52.100
   Sent 5 probes (5 broadcast(s))

📋 SAU KHI CHỮA — không hề đụng vào client hay router:
   router(.52):   02:56:9d:32:8f:61    -> node-b
   client-lan:    02:56:9d:32:8f:61    -> node-b
```

**Vì sao hoạt động.** GARP là một gói ARP Request broadcast trong đó **Sender IP
== Target IP**. Nó không hỏi gì cả — nó khai báo. Mọi thiết bị trong broadcast
domain nghe thấy đều cập nhật bảng ARP của mình. Router nằm trong domain đó nên
nó cập nhật theo, và toàn bộ client ở các subnet khác được cứu gián tiếp.

**Vì sao `-c 5` chứ không phải `-c 3`.** GARP là broadcast: không ACK, không
retransmit, mất là mất luôn. Khi có switch/router doanh nghiệp ở giữa (buffer
đầy, storm-control, Dynamic ARP Inspection) thì 3 gói là mỏng. Bắn 5 gói tốn
thêm vài mili-giây, đổi lại đỡ phải giải thích vì sao dịch vụ chết thêm 4 tiếng.

**Nhưng đây vẫn là chữa triệu chứng.** Lần failover sau, script tự chế lại quên
lần nữa. Chữa gốc: vứt script đi dùng Keepalived, hoặc dùng `use_vmac` (KB12).

**Dòng lệnh này nằm ở đâu trong các stack thật:**

| Stack | GARP |
| :--- | :--- |
| keepalived | tự động, không cần khai báo |
| pacemaker `ocf:heartbeat:IPaddr2` | có, chỉnh qua `arp_count` / `arp_bg` |
| pacemaker `IPaddr` (bản cũ) | **không** |
| script tự viết | **phải tự thêm** `arping -U` ngay sau `ip addr add` |

---

## KB5 — Không chữa gì: Linux 32 giây, Cisco 4 tiếng

**Tình huống ngoài đời.** Bạn test lab trên Linux, thấy "kệ nó, 30 giây tự khỏi",
rồi yên tâm ship lên production chạy Cisco. Đây là kịch bản đắt nhất của tập.

**Chạy:** (mất ~5 phút, có hai phần)
```bash
./scripts/5-tu-khoi.sh
```

**Thấy gì — PHẦN 1, router Linux:**
```
   client-remote:   TỰ KHỎI sau ~32 giây
   client-lan:      cũng đã sống (chung một bảng ARP được sửa)
```

**Thấy gì — PHẦN 2, router giả lập Cisco:**
```
🔧 Giả lập ARP timeout kiểu Cisco IOS trên chân eth1 của router:
     base_reachable_time_ms = 14400000   (4 tiếng)

   ❌ VẪN CHẾT sau 90 giây.
      172.28.52.100 lladdr e2:da:01:55:01:86 REACHABLE
      ↑ Vẫn REACHABLE với MAC của máy đã chết.
```

**Vì sao khác nhau.** Linux có **NUD** (Neighbour Unreachability Detection): khi
thấy một entry im lặng quá lâu, nó tự gửi ARP probe hỏi lại. Đó là **may mắn,
không phải thiết kế** — chuẩn ARP (RFC 826) không có nghĩa vụ này. Thiết bị mạng
chuyên dụng không có NUD; chúng chỉ có timer đếm ngược, và timer đó rất dài.

| Thiết bị | ARP timeout | Có NUD? | Tự khỏi sau |
| :--- | :--- | :--- | :--- |
| Linux (host/router) | ~30–60 giây | **CÓ** | ~30–50 giây |
| Juniper JunOS | 1200 giây | KHÔNG | 20 phút |
| Cisco NX-OS | 1500 giây | KHÔNG | 25 phút |
| **Cisco IOS / IOS-XE** | **14400 giây** | KHÔNG | **4 TIẾNG** |

**Tệ hơn nữa:** với CEF adjacency trên Cisco, gói bị drop **im lặng** — không
sinh log, không tăng counter interface. Không có gì để bạn tìm ra.

**Gặp ở đâu.** Mọi cụm HA có client ở subnet khác. Con số 4 tiếng không phải nói
quá — nó là mặc định của IOS, và gần như không ai đổi.

---

## KB6 — Chữa cháy từ phía router

**Tình huống ngoài đời.** 3 giờ sáng. Dịch vụ chết. Bạn chưa biết vì sao node-b
không bắn GARP, team server chưa ai bốc máy. Nhưng bạn có quyền vào router.

**Chạy:**
```bash
./scripts/6-chua-tren-router.sh
```

**Thấy gì:**
```
📋 TRƯỚC KHI CHỮA:
   router(.52):   0e:56:b4:94:59:c3    -> node-a ĐÃ CHẾT
   client-lan:    0e:56:b4:94:59:c3    -> node-a ĐÃ CHẾT
   lab05-client-remote      CHẾT
   lab05-client-lan         CHẾT

💊 docker exec lab05-router ip neigh del 172.28.52.100 dev eth1

📋 SAU KHI CHỮA:
   router(.52):   02:56:9d:32:8f:61    -> node-b
   client-lan:    0e:56:b4:94:59:c3    -> node-a ĐÃ CHẾT
   lab05-client-remote      SỐNG  ✅
   lab05-client-lan         CHẾT  ❌ (chưa ai chữa cho máy này)
```

**Đây là kết quả quan trọng nhất của nhóm B.** Chữa router thì `client-remote`
sống lại **ngay lập tức**, mà `client-lan` **vẫn chết**. Chứng minh dứt khoát:
mỗi thiết bị trong broadcast domain ôm một bảng ARP **riêng**, ốm **độc lập**.
Đó chính là lý do cách chữa ĐÚNG (KB4) phải là GARP broadcast — nó chữa tất cả
cùng một lúc.

**Lệnh tương đương trên thiết bị thật:**
```
Cisco IOS   : clear ip arp 172.28.52.100
Cisco NX-OS : clear ip arp 172.28.52.100 vrf all
Juniper     : clear arp hostname 172.28.52.100
```

**Ba cảnh báo:**
1. Lần failover sau lại chết y hệt — đây là chữa cháy, không phải chữa bệnh.
2. Đừng gõ `clear arp-cache` toàn cục giờ cao điểm: nó rớt hết neighbor của mọi
   VLAN cùng lúc. Xoá **đúng một IP** thôi.
3. Sysadmin thường **không** có quyền vào router. Trong sự cố thật, bước này
   phải chờ team mạng — cộng thêm 20 phút downtime.

---

## KB7 — GARP dừng lại ở biên Tầng 3

**Tình huống ngoài đời.** Ai đó trong cuộc họp postmortem đề xuất: "vậy cứ cấu
hình bắn thật nhiều GARP là xong chứ gì". Đúng một nửa, và nửa sai là nửa quan
trọng.

**Chạy:**
```bash
./scripts/7-garp-khong-xuyen-router.sh
```

**Thấy gì:**
```
   router chân eth1 (LB LAN):        5 gói ✅ có nhận
   router chân eth0 (client LAN):    0 gói ← router KHÔNG chuyển tiếp sang
   client-remote eth0:               0 gói ← KHÔNG hề biết có chuyện gì

   04:38:27 6a:28:33:13:ce:6e > ff:ff:ff:ff:ff:ff, ARP,
            Request who-has 172.28.52.100 tell 172.28.52.100
```

**Vì sao.** ARP là giao thức Tầng 2. GARP là broadcast Ethernet tới
`ff:ff:ff:ff:ff:ff`, và router **không bao giờ** chuyển tiếp broadcast Tầng 2
sang subnet khác — nếu có thì mọi mạng lớn đã sập vì broadcast storm từ lâu.

👉 Nói cho chính xác: **GARP không sửa client remote. Nó sửa ROUTER.** Client
remote được cứu gián tiếp vì nó gửi mọi thứ qua router.

**Ba hệ quả khi đi soi sự cố:**
1. Bắt gói ở client remote để tìm GARP = chắc chắn không thấy gì. Phải bắt ở một
   máy **cùng subnet với VIP**.
2. **Mọi** thiết bị L3 có chân trong subnet của VIP đều cần được cập nhật:
   router chính, router dự phòng, firewall, load balancer ngoài, peer HSRP/VRRP.
   Thiếu một cái là còn một đường chết.
3. Bắt gói **trên chính node vừa failover là vô nghĩa** — ở đó lúc nào cũng thấy
   gói đi ra. Phải bắt ở **máy thứ ba**.

**Công cụ:**
```bash
./scripts/bat-goi-garp.sh            # bắt ở router (mặc định, đúng chỗ)
./scripts/bat-goi-garp.sh client     # bắt ở client-lan
./scripts/bat-goi-garp.sh remote     # bắt ở client-remote — sẽ trống trơn
```

---

# NHÓM C — Cụm HA Tự Đánh Nhau

Hai kịch bản này không phải "thiếu GARP" mà là cụm HA tự gây hại cho chính mình.

## KB8 — Split-brain: thừa GARP từ hai nguồn

**Tình huống ngoài đời.** Đứt đường VRRP heartbeat (VLAN sai, switch chặn
multicast `224.0.0.18`, firewall chặn protocol 112, link heartbeat riêng chết) —
trong khi **cả hai node vẫn sống và vẫn phục vụ được**.

**Chạy:**
```bash
./scripts/8-split-brain.sh
```

**Thấy gì — bằng chứng chắc chắn:**
```
   node-a giữ VIP: CÓ
   node-b giữ VIP: CÓ
   ❌ SPLIT-BRAIN: hai máy cùng mang một địa chỉ IP trên cùng một LAN.

   ARPING 172.28.52.100 from 172.28.52.20 eth0
   Unicast reply from 172.28.52.100 [B6:B2:35:8B:E8:83]  0.535ms
   Unicast reply from 172.28.52.100 [8E:53:60:41:69:D0]  0.538ms
   ...
   Sent 4 probes (1 broadcast(s))
   Received 5 response(s)
```

👉 **SỐ ĐÁP > SỐ HỎI, và đến từ HAI MAC khác nhau.** Đây là dấu vân tay kinh
điển của duplicate IP. Trên hệ thống thật, đây là lệnh đầu tiên nên gõ khi nghi
ngờ:
```bash
arping -c 4 -I <iface> <VIP>
```

> ⚠️ **Đọc bảng ARP trong kịch bản này cho đúng.** Trong lab, gần như lượt nào
> cũng ra cùng một node — vì hai node nằm trên cùng một Linux bridge của Docker,
> độ trễ chênh nhau vài chục micro-giây nên cuộc đua ARP có kẻ thắng **ổn định**.
> **Đừng kết luận "split-brain thì bảng ARP luôn đứng yên".** Ngoài đời hai node
> nằm ở hai rack, hai switch, hai uplink khác nhau; kẻ thắng đổi theo tải và
> theo đường đi, và **mỗi thiết bị trong LAN có thể chốt một kẻ thắng khác nhau**.
> Bằng chứng chắc chắn nằm ở kết quả `arping`, không nằm ở bảng ARP.

**Vì sao tệ hơn "quên GARP":**

| | Quên GARP (KB3) | Split-brain (KB8) |
| :--- | :--- | :--- |
| Kiểu hỏng | dứt khoát | **chập chờn** |
| Dễ tìm không | dễ, có chữ ký rõ | khó, lỗi ngẫu nhiên |
| Tự khỏi | có (nếu router Linux) | không |
| Với dịch vụ ghi dữ liệu | mất kết nối | **MẤT DỮ LIỆU** — hai MASTER cùng ghi |

**Phòng tránh:**
- Đường heartbeat **riêng**, tốt nhất hai đường độc lập
- `unicast_peer` thay cho multicast (qua được switch chặn multicast)
- Quorum / STONITH (Pacemaker) để ép chỉ một node được sống
- Giám sát: cảnh báo ngay khi thấy 2 MAC cùng đáp cho 1 VIP

---

## KB9 — Một sự cố, hai lần mất phiên

**Tình huống ngoài đời.** Node chính chết lúc 2 giờ sáng, node phụ gánh ngon
lành. 8 giờ sáng bạn sửa xong node chính và bật lại — dịch vụ đứt **lần thứ
hai**, ngay giữa giờ cao điểm, do chính tay bạn.

**Chạy:** (mất ~4 phút, hai phần)
```bash
./scripts/9-preempt.sh
```

**Thấy gì:**
```
# PHẦN 1 — MẶC ĐỊNH (preempt bật)
   Kết nối #1 (lúc node-a chết) : 614400/2097152 bytes  curl_exit=18
   Kết nối #2 (lúc node-a về)   : 1536000/2097152 bytes curl_exit=28
👉 CẢ HAI kết nối đều đứt.

# PHẦN 2 — BẬT nopreempt
   Kết nối #1 (lúc node-a chết) : 614400/2097152 bytes  curl_exit=18
   Kết nối #2 (lúc node-a về)   : 2097152/2097152 bytes curl_exit=0
👉 Kết nối #2 SỐNG SÓT.
```

**Vì sao.** Mặc định VRRP là **preemptive**: node nào priority cao hơn thì luôn
giành lại VIP khi nó quay lại, kể cả khi node đang giữ chạy hoàn toàn tốt. Mỗi
lần VIP chuyển là một lần mọi phiên TCP đang mở bị giết (đúng lý do của KB2).

⚠️ **Đây là lý do đo HA bằng `ping` là chưa đủ.** Lần chuyển thứ hai gần như
không rớt gói ICMP nào — nhưng vẫn giết sạch session đang mở.

**Chọn thế nào:**

| | Dùng khi |
| :--- | :--- |
| `preempt` (mặc định) | hai node **không** ngang nhau — node chính mạnh hơn hẳn, node phụ chỉ gánh tạm |
| `nopreempt` | hai node **ngang nhau** — đa số trường hợp. Đã chạy tốt trên node-b thì không có lý do gì chuyển ngược |
| `preempt_delay <giây>` | ở giữa: chờ node vừa hồi phục ổn định rồi mới giành lại, tránh flapping |

> 🪤 `nopreempt` **chỉ hợp lệ khi `state BACKUP`**. Đặt `state MASTER` kèm
> `nopreempt` thì keepalived báo lỗi và bỏ qua dòng đó.

---

# NHÓM D — Chết Vì Lý Do KHÁC Tầng 2

Ba kịch bản cuối tách bạch những ca **trông giống hệt** ca bệnh chính nhưng có ổ
bệnh hoàn toàn khác — và cách chữa tận gốc.

## KB10 — Dịch vụ chết nhưng máy vẫn sống

**Tình huống ngoài đời.** HAProxy crash, hoặc nginx bị OOM-kill. Máy vẫn ping
được, VRRP vẫn chạy ngon, keepalived vẫn thấy peer khoẻ. Nếu không có
`track_script`, VIP sẽ nằm im trên một máy không phục vụ được gì.

**Chạy:**
```bash
./scripts/10-dich-vu-chet.sh
```

**Thấy gì:**
```
💥 Giết HAProxy trên node-a (KHÔNG đụng vào Keepalived, máy vẫn sống)...
   t+2  s  VIP=node-a      HTTP=000
   t+4  s  VIP=node-a      HTTP=000
   t+6  s  VIP=node-b      HTTP=200
```

**Vì sao ~6 giây.** `interval 2` × `fall 2` = 4 giây để `chk_haproxy` kết luận
đã hỏng, cộng thời gian VRRP chuyển trạng thái. Khi script fail, priority bị trừ
`weight -30`: 110 − 30 = 80 < 100 của node-b → node-b lên MASTER.

```
vrrp_script chk_haproxy {
    script "/usr/local/bin/check_haproxy.sh"
    interval 2
    timeout 2
    weight -30      # 110 - 30 = 80 < 100 -> node-b cướp VIP
    fall 2
    rise 2
}
```

> 🪤 **Bẫy chí mạng khi tự dựng lại.** Script health-check **phải** bake vào
> image với quyền `root:root 0755`. Bind-mount từ host thì file mang UID của
> user host, và keepalived (bật `enable_script_security`) sẽ từ chối chạy:
> `Unsafe permissions found for script ... - disabling`. `track_script` bị vô
> hiệu hoá **âm thầm** — dịch vụ chết mà VIP vẫn nằm im, y như chưa cấu hình gì.

---

## KB11 — Mất backend sau router → HTTP 503

**Tình huống ngoài đời.** Người dùng báo y hệt KB3: "cụm HA vừa failover xong,
dịch vụ không vào được". Nhưng lần này ổ bệnh không ở bảng ARP mà ở một rule
firewall vừa đổi giữa vùng DMZ và vùng app.

**Chạy:**
```bash
./scripts/11-backend-qua-router.sh
```

**Thấy gì:**
```
PHẦN: router chặn .52 -> .53 bằng DROP  (gói bị nuốt im lặng — giống tập 01)
   Trước khi chặn: web-1=UP web-2=UP
   ⏱  HAProxy đánh dấu cả 2 backend DOWN sau ~8 giây
   Client nhận:    HTTP 503 trong 0.000346s

PHẦN: router chặn .52 -> .53 bằng REJECT (gói bị từ chối có báo lại — giống tập 02)
   ⏱  HAProxy đánh dấu cả 2 backend DOWN sau ~4 giây
   Client nhận:    HTTP 503 trong 0.000344s
```

**DROP 8 giây vs REJECT 4 giây.** Đúng bài học của tập 01 và tập 02: `DROP` bắt
health check phải chờ hết `timeout connect 2s` mỗi lần, `REJECT` trả lời ngay
nên HAProxy kết luận nhanh gấp đôi. Cùng một hậu quả, khác nhau thời gian phát
hiện.

**Bảng phân biệt ba ca "dịch vụ chết" trông giống hệt nhau:**

| Dấu hiệu | KB3 (ARP cũ) | KB11 (mất backend) | KB10 (HAProxy chết) |
| :--- | :--- | :--- | :--- |
| `curl` trả về | **(28) timeout** | **HTTP 503** | 200 (sau ~7s) |
| **Có response HTTP?** | **KHÔNG** | **CÓ** | CÓ |
| VIP có chuyển không | đã chuyển rồi | **KHÔNG** | có, tự chuyển |
| Bảng ARP router | **SAI** (MAC chết) | ĐÚNG | ĐÚNG |
| HAProxy stats | **backend UP hết** | **backend DOWN hết** | node kia phục vụ |
| Sửa ở đâu | node đang giữ VIP | router / firewall | không cần sửa |

👉 **"Có response hay không" là câu hỏi đầu tiên phải trả lời trong mọi sự cố.**
Có response nghĩa là gói đã đi tới nơi về tới chốn — Tầng 2 và Tầng 3 đều ổn,
đừng phí thời gian soi ARP.

👉 **Dòng "HAProxy stats" lật ngược trực giác:**
- **KB3**: monitoring báo **xanh hết** mà dịch vụ chết. Monitoring bị mù, vì
  HAProxy chỉ nhìn **xuống** backend, không biết gì về bảng ARP ở phía **trên** nó.
- **KB11**: monitoring báo **đỏ đúng chỗ**. Đây là ca dễ — nếu bạn chịu mở trang
  stats ra xem thay vì đoán.

**Gặp ở đâu.** Đổi rule firewall DMZ ↔ app, siết security group / NACL, ACL trên
core switch, bật microsegmentation. Thường **không liên quan gì** tới cụm HA —
nhưng vì sự cố nổ ra ngay sau một lần failover nên ai cũng đổ tội cho HA trước.

---

## KB12 — Chữa tận gốc: `use_vmac`

**Tình huống ngoài đời.** Bạn đã chữa xong sự cố và muốn nó **không bao giờ xảy
ra lại**, thay vì mỗi lần lại đi kiểm tra xem GARP có được bắn không.

**Chạy:** (mất ~2 phút, hai phần)
```bash
./scripts/12-use-vmac.sh
```

**Thấy gì:**
```
PHẦN 1 — KEEPALIVED MẶC ĐỊNH: MAC ĐỔI khi failover
   MAC router ôm TRƯỚC failover: 7a:b2:41:ca:85:db
   MAC router ôm SAU failover:   3e:8a:a6:b6:33:ff     ← ĐỔI

PHẦN 2 — use_vmac: MAC KHÔNG ĐỔI
      vrrp51@eth0: MAC 00:00:5e:00:01:33
      IP 172.28.52.100/24
   MAC router ôm TRƯỚC failover: 00:00:5e:00:01:33
   MAC router ôm SAU failover:   00:00:5e:00:01:33     ← KHÔNG ĐỔI
```

**Vì sao.** `use_vmac` lật ngược toàn bộ vấn đề. Keepalived tạo một interface
macvlan mang MAC ảo theo chuẩn VRRP:

```
00:00:5e:00:01:<VRID>       ->  00:00:5e:00:01:33   (0x33 = 51 = virtual_router_id)
```

MAC này **giống hệt nhau trên mọi node** trong nhóm. Node nào lên MASTER thì
interface đó UP trên máy đó. Với router, VIP vẫn ứng đúng một MAC như cũ —
**không có gì để cập nhật, nên cũng không có gì để quên.**

Toàn bộ ca bệnh của tập này biến mất: không cần GARP, không lo switch nuốt gói,
không lo STP chưa forward, không lo ARP timeout 4 tiếng của Cisco.

**Cấu hình:**
```
vrrp_instance VI_LB {
    use_vmac vrrp51
    vmac_xmit_base      # phát VRRP advertisement ra interface THẬT
    ...
}
```

**Vậy sao keepalived để mặc định TẮT? Giá phải trả:**
- macvlan không chạy được ở mọi nơi: một số hypervisor, cloud VPC và switch bật
  port-security sẽ chặn frame có MAC lạ
- Cổng switch nhìn thấy 2 MAC trên 1 cổng → đụng giới hạn port-security
- Khó soi hơn: `00:00:5e:00:01:xx` không tra ra được máy nào đang giữ VIP
- **VRID phải DUY NHẤT trong cùng broadcast domain.** Hai cụm HA cùng dùng VRID
  51 trên một VLAN = hai cụm cùng một MAC ảo = hỏng cả hai

**Khuyến nghị.** Hạ tầng bạn kiểm soát được Tầng 2 (bare-metal, VLAN riêng) thì
bật `use_vmac`. Chạy trên cloud/hypervisor lạ thì giữ mặc định và đảm bảo GARP
được bắn đủ (KB4).

---

## 🧹 Dọn dẹp

```bash
docker compose down -v
```
