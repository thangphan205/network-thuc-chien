# 💡 Cơm Thêm: Có Router Đứng Giữa Thì Ca Bệnh Đi Đâu?

> Tài liệu bổ trợ **kèm lab chạy được** cho **Tập 05: Failover HA Thành Công Nhưng Dịch Vụ Vẫn Chết**.
> Lab nằm ở thư mục `com-them-router/`, chạy độc lập với lab chính.

---

## 0. Câu hỏi khởi nguồn

Lab chính đặt client và server **cùng một subnet**. Đời thật hiếm khi vậy: client ngồi ở VLAN văn phòng, server nằm trong VLAN DMZ, giữa hai bên là router hoặc L3 switch.

Mà client khác subnet thì **client không bao giờ ARP hỏi VIP** — nó chỉ ARP hỏi default gateway. Vậy triệu chứng "client ôm MAC của node MASTER đã chết" **biến mất thật**.

Câu hỏi: **hết bệnh chưa?**

**Chưa.** Bệnh không biến mất, nó **đổi chỗ**. Và đổi theo hướng tệ hơn nhiều.

---

## 1. Sơ đồ lab Cơm Thêm

```
+----------------------------+     +-------------------+     +----------------------------+
| SUBNET CLIENT 172.28.6.0/24|     |      ROUTER       |     | SUBNET SERVER 172.28.7.0/24|
+----------------------------+     +-------------------+     +----------------------------+
|                            |     |                   |     |                            |
|   [client] .6.20           |=====| .6.254     .7.254 |=====|   [node-a] .11   >> DEAD   |
|                            |     |                   |     |   [node-b] .12   << VIP    |
|   ARP TABLE                |     | ARP TABLE         |     |                            |
|     .6.254 -> router MAC   |     |   .7.100 -> MAC   |     |   VIP 172.28.7.100         |
|     (NO entry for VIP)     |     |     of node-a     |     |   now lives on node-b      |
|                            |     |   ^^^^^^^^^^^^^^^ |     |                            |
|          CLEAN             |     |     STALE = SICK  |     |         HEALTHY            |
+----------------------------+     +-------------------+     +----------------------------+
```

> 🔑 Một câu tóm gọn: **client vô can, server khoẻ mạnh, ổ bệnh nằm trên thiết bị mà đội ứng dụng thường không có quyền đăng nhập.**

---

## 2. Chạy lab

```bash
cd network-bat-benh/tap-05-vip-failover-garp/com-them-router
docker compose up -d --build

./scripts/0-setup.sh     # dựng trạng thái bình thường
./scripts/1-fault.sh     # failover, quên GARP
./scripts/test.sh        # chẩn đoán 6 bước
```

Các kịch bản phụ:

| Script | Chứng minh điều gì |
| :--- | :--- |
| `3-tu-khoi.sh` | Đo downtime khi không chữa gì |
| `4-chua-chay-tren-router.sh` | Entry sai trên router là nguyên nhân **duy nhất** |
| `5-hai-ma-loi.sh` | Bảng ARP **sai** nguy hiểm hơn bảng ARP **trống** |
| `6-garp-khong-xuyen-router.sh` | GARP dừng ở biên L3, nhưng vẫn tới được router |

Dọn dẹp: `docker compose down`.

---

## 3. Hai bảng ARP — ai biết gì về ai

Output thật của `./scripts/0-setup.sh`:

```
   [CLIENT] — KHÔNG hề có dòng nào cho VIP 172.28.7.100, chỉ biết mỗi router:
     172.28.6.254 dev eth0 lladdr ee:96:e3:45:41:46 REACHABLE

   [ROUTER] interface phía server (eth1) — đây mới là thằng ôm MAC của VIP:
     172.28.7.100 lladdr 72:34:04:e8:ba:73 REACHABLE
```

Đọc kỹ: bảng ARP của client **chỉ có đúng một dòng — router**. Nó không biết, không cần biết, và sẽ không bao giờ biết VIP ứng với MAC nào.

Thằng đi ARP hỏi VIP, nhận câu trả lời, rồi ôm cái MAC đó là **router**.

---

## 4. Bốn triệu chứng đổi khác

### 4.1. Manh mối "im lặng" của lab chính biến mất sạch

Ở lab chính, chẩn đoán nằm ở chỗ: client ôm MAC sai **và** không có gói ARP nào được hỏi lại. Giờ thì `tcpdump` ở client chỉ thấy gói đi ra với MAC của router — **hoàn toàn bình thường**. Không dấu hiệu bất thường nào.

**Debug ở phía client là ngõ cụt 100%.** Bảng ARP sạch, route đúng, gateway ping được. Càng soi càng thấy client vô tội — vì nó vô tội thật.

### 4.2. Chữ ký đặc trưng: đứt MỘT CHIỀU

Output `BƯỚC 5` của `test.sh`:

```
🩺 [BƯỚC 5] Chiều NGƯỢC LẠI: node-b gọi client:
64 bytes from 172.28.6.20: icmp_seq=1 ttl=63 time=0.123 ms
64 bytes from 172.28.6.20: icmp_seq=2 ttl=63 time=0.283 ms
2 packets transmitted, 2 received, 0% packet loss
```

node-b ping ngược ra client: **thông tuyệt đối**. Vì node-b chỉ cần ARP hỏi router, và router trả lời tươi rói.

Nên kỹ sư SSH vào node-b kiểm tra sẽ thấy: gateway OK, ping client OK, ra internet OK, nginx OK, VIP có trên interface. **Tất cả đều xanh.** Chỉ mỗi chiều **vào** VIP là chết.

Bất đối xứng kiểu này chính là dấu vân tay của ca bệnh.

### 4.3. `traceroute` chết ngay SAU hop router cuối

```
traceroute to 172.28.7.100, 5 hops max
 1  172.28.6.254  0.005 ms      <- qua duoc router
 2  *
 3  *
```

Đi qua được router, rồi tắt lịm. Đó là chỉ điểm: gói **tới được** router, chết ở **chặng L2 cuối cùng** mà router phải đi.

### 4.4. Blackhole im lặng — và đây là chỗ nguy hiểm nhất

Router **không** gửi ICMP Host Unreachable, vì với nó ARP đã resolve thành công rồi. Nó tin chắc mình biết MAC.

`5-hai-ma-loi.sh` đo hai trường hợp — **cả hai đều là "dịch vụ không chạy"**, nhưng hệ thống báo về hai kiểu trái ngược:

```
🔸 [1] Router KHÔNG có entry -> ARP hỏi, không ai đáp -> ARP THẤT BẠI trung thực:
     curl: (7) Failed to connect to 172.28.7.100:80 after 3071 ms: Could not connect to server

🔸 [2] Router ÔM ENTRY SAI -> ARP 'thành công' vào hư vô -> BLACKHOLE IM LẶNG:
     curl: (28) Connection timed out after 5004 milliseconds
```

| | Bảng ARP **trống** | Bảng ARP **sai** |
| :--- | :--- | :--- |
| Hành vi router | ARP hỏi → không ai đáp → trả ICMP Host Unreachable | Gửi frame tới MAC ma → im lặng |
| curl báo | `(7) Could not connect` — **~3 giây** | `(28) Timed out` — **treo hết timeout** |
| Có log/alert không | Có. Lỗi rõ ràng, monitor bắt được | Không. Không ai báo gì cả |
| Kỹ sư mất bao lâu | Vài phút | Hàng giờ |

> 🔑 **Bảng ARP SAI nguy hiểm hơn bảng ARP TRỐNG.** Trống thì hệ thống trung thực báo lỗi cho bạn. Sai thì nó im lặng nuốt gói, và mọi công cụ đều nói "không có gì bất thường".

---

## 5. Mất luôn "tự khỏi sau 30 giây" — phần đáng sợ nhất

Chuỗi `REACHABLE → STALE → DELAY → PROBE → FAILED` là **state machine NUD của kernel Linux**. Router thương mại **không chạy cái đó** — chúng chỉ có một timer aging đơn giản.

Lab này dùng router mềm chạy Linux, nên vẫn còn tự khỏi. Đo thật:

```
💡 TỰ KHỎI sau ~34 giây.
>>> wall-clock bao ngoài: 35s
```

Cùng cơ chế NUD nên con số dao động giống lab chính (~30–50 giây).

**Nhưng thay Linux bằng thiết bị thật thì bức tranh đổi hẳn:**

| Nền tảng | ARP aging mặc định | Có tự khỏi kiểu NUD không |
| :--- | :--- | :--- |
| Linux (router mềm) | ~30–50s | **Có** |
| Juniper | 1200s (20 phút) | Không — chỉ chờ hết timer |
| Cisco NX-OS | 1500s (25 phút) | Không |
| **Cisco IOS** | **14400s = 4 TIẾNG** | Không |

> ⚠️ Số mặc định theo hãng, **luôn kiểm bằng `show arp` / `show ip arp` trên thiết bị thật** trước khi tin.

Hệ quả: câu chuyện đổi từ *"chờ nửa phút là tự vào được"* thành **outage thật, kéo dài, không tự khỏi**. Ticket không còn bị đóng với lý do "chập chờn không tái hiện được" — nó thành sự cố P1 và bạn phải đi tìm người có quyền vào router lúc 2 giờ sáng.

> 🧩 **Trên L3 switch còn thêm một lớp nữa:** CEF adjacency table cache sẵn MAC rewrite. Clear ARP xong đôi khi vẫn phải chờ adjacency rebuild.

---

## 6. Cách chữa KHÔNG đổi — và vì sao nó vẫn hiệu quả

GARP là **broadcast trong subnet của VIP**. Router có một chân trong subnet đó → **router vẫn nghe được**.

`6-garp-khong-xuyen-router.sh` bắt gói đồng thời hai phía trong lúc node-b phát GARP:

```
[ROUTER — chân phía server] nhận được:
   42:b7:92:11:6b:f4 > ff:ff:ff:ff:ff:ff, ARP, Request who-has 172.28.7.100 tell 172.28.7.100
   42:b7:92:11:6b:f4 > ff:ff:ff:ff:ff:ff, ARP, Request who-has 172.28.7.100 tell 172.28.7.100
   42:b7:92:11:6b:f4 > ff:ff:ff:ff:ff:ff, ARP, Request who-has 172.28.7.100 tell 172.28.7.100

[CLIENT — khác subnet] nhận được:
   (KHÔNG một gói GARP nào — broadcast dừng lại ở biên L3)
```

Đúng như thiết kế: GARP **không** xuyên qua router, và **không cần** xuyên qua. Nó chỉ cần chạm tới đúng thiết bị đang ôm entry sai.

Nên lệnh chữa vẫn y nguyên, vẫn gõ trên node-b:

```bash
arping -U -c 5 -I eth0 172.28.7.100
```

**Ba lưu ý riêng cho trường hợp có router:**

1. **Gửi nhiều gói hơn** — 5 thay vì 3. Router bận, một gói broadcast rơi là ôm entry sai thêm 4 tiếng nữa.
2. **Router có thể cố tình bỏ qua GARP** — Dynamic ARP Inspection, port security, hoặc cấu hình tắt hẳn gratuitous ARP. Lúc đó phải đi đường chữa cháy ở mục 7.
3. **Có bao nhiêu thiết bị L3 chân trong subnet đó thì phải update từng ấy** — router chính, router backup, firewall, load balancer. Broadcast tới hết, nhưng thiết bị nào chặn GARP thì phải xử riêng.

---

## 7. Đường chữa cháy: gõ tay trên router

Khi GARP bị nuốt, không còn cách nào ngoài vào thẳng router. `4-chua-chay-tren-router.sh`:

```
🔸 [A] Router đang ôm ENTRY SAI (MAC của node-a đã chết):
     172.28.7.100 lladdr 22:ed:35:72:eb:18 REACHABLE
     curl từ client -> curl: (28) Connection timed out after 5012 milliseconds

🔸 [B] Xoá entry sai đó khỏi router — KHÔNG chạm gì vào node-b, KHÔNG phát GARP:
     Lệnh trên router:  ip neigh del 172.28.7.100 dev eth1
     curl từ client -> <h1>TOI LA NODE B (BACKUP)</h1>

     172.28.7.100 lladdr 42:b7:92:11:6b:f4 REACHABLE
```

Thông ngay lập tức. Router tự ARP lại, node-b trả lời, xong. **Chứng minh dứt điểm: entry sai trên router là nguyên nhân duy nhất.**

Lệnh tương đương trên thiết bị thật:

```
clear ip arp 172.28.7.100          # Cisco IOS
clear arp-cache                     # Cisco IOS - xoa toan bo
clear arp interface ge-0/0/0        # Juniper
ip neigh del 172.28.7.100 dev eth1  # Linux
```

> ⚠️ Nhưng đây **chỉ là chữa cháy**, không phải cách làm đúng:
> * phải có quyền SSH/enable vào router — đội ứng dụng thường không có;
> * có bao nhiêu thiết bị L3 trong subnet thì phải gõ bấy nhiêu lần;
> * lần failover sau lặp lại y nguyên.
>
> Cách đúng vẫn là `arping` trên node vừa failover — một lệnh, sửa cho tất cả cùng lúc, và tự động hoá được vào script failover.

---

## 8. Quy trình chẩn đoán khi nghi ngờ có router ở giữa

```bash
# 1. Trên CLIENT: xác nhận client VÔ CAN (dự kiến: mọi thứ sạch)
ip neigh show                    # KHÔNG có VIP, chỉ có gateway -> đúng như dự kiến
ip route get <VIP>               # xem gói sẽ đi ra gateway nào
traceroute <VIP>                 # chết ngay sau hop router cuối

# 2. Trên NODE vừa failover: xác nhận server KHÔNG phải thủ phạm
ip addr show | grep <VIP>        # VIP có trên interface
ss -tlnp | grep :80              # service đang nghe
ping <IP-client>                 # THÔNG -> chiều ra sống, chiều vào chết = bất đối xứng

# 3. Trên ROUTER: đây mới là ổ bệnh
show ip arp | include <VIP>      # Cisco
show arp | match <VIP>           # Juniper
ip neigh show <VIP>              # Linux
# -> so MAC này với MAC thật của node vừa lên MASTER. Lệch = bắt được bệnh.
```

---

## 🎯 9. Đúc kết

1. **Có router ở giữa không làm ca bệnh biến mất — nó chuyển nạn nhân từ client sang router.** Cơ chế y hệt, chỉ đổi thằng ôm MAC chết.

2. **Triệu chứng khó đọc hơn hẳn:** client sạch trơn, server toàn xanh, chỉ đứt một chiều. Ba dấu hiệu đáng tin duy nhất là **bất đối xứng chiều vào/chiều ra**, **traceroute chết ngay sau router**, và **`curl` timeout thay vì báo lỗi**.

3. **Mất luôn cơ chế tự khỏi.** Linux còn NUD nên ~35 giây. Router thương mại chỉ có timer aging — Cisco IOS mặc định **4 tiếng**. Từ "chập chờn khó chịu" thành "outage thật".

4. **Cách chữa không đổi:** `arping -U` trên node vừa failover. GARP dừng ở biên L3, nhưng router có chân trong subnet VIP nên vẫn nghe được — một lệnh sửa cho toàn bộ client ở mọi subnet phía sau.

5. **Bảng ARP sai nguy hiểm hơn bảng ARP trống.** `curl: (7)` là hệ thống trung thực báo lỗi. `curl: (28)` là hệ thống im lặng nuốt gói. Ca bệnh này luôn cho bạn cái thứ hai.

---

## 🧹 Dọn dẹp

```bash
cd com-them-router && docker compose down
```
