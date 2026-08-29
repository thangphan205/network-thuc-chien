# 🩺 Ca Bệnh 04: Path MTU Blackhole — Ping Gói Nhỏ OK, Web Tải Nửa Chừng Thì Đơ

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Người dùng ping máy chủ thấy cực kỳ mượt mà. Mở website thì tiêu đề trang vừa hiện lên nhưng sau đó trang web **quay vòng vòng vô tận**. Chạy `curl` thì thấy triệu chứng đắt giá nhất: **`HTTP 200` nhưng `tải về 0 bytes`** — header HTTP (nhỏ) về được, body HTML (to) thì không bao giờ tới.
> * **Bản chất lỗi:** **Path MTU Discovery (PMTUD) Blackhole**. Gói tin kích thước nhỏ (Ping 64B, TCP SYN 60B, HTTP header 239B) đi qua thông suốt, nhưng gói dữ liệu lớn vượt MTU đường truyền bị thiết bị trung gian **âm thầm hủy (DROP)** mà không gửi về ICMP `Fragmentation Needed` (Type 3 Code 4) — nên hai đầu không hề biết mà tự giảm kích thước.

> 📚 **Điều kiện tiên quyết:** Nắm được `ping`, `curl`, `tcpdump` ở mức cơ bản (xem series **Debug Mạng A-Z**) và đã học qua [Tập 01 — Firewall DROP](../tap-01-firewall-drop). Hai ca cùng bản chất "im lặng vứt gói", khác ở **thời điểm treo**: Tập 01 treo ngay lúc **bắt tay TCP**, Tập 04 bắt tay xong xuôi rồi mới treo lúc **truyền data**.

---

## 🔬 Sơ đồ Kiến trúc Lab

```text
   DOCKER NETWORK 172.28.4.0/24
   [Client: 172.28.4.20]                        [Web Server: 172.28.4.10]
             |                                              |
             |  1. ping 64B  ------------------------------>| PASS   gói nhỏ, qua lọt
             |  2. TCP SYN (60B)  ------------------------->| PASS   bắt tay TCP xong
             |  3. GET / (75B)  --------------------------->| PASS   request nhỏ, qua lọt
             |                                              |
             | <----- 4. HTTP/1.1 200 OK header (239B) -----| PASS   nên curl báo HTTP 200
             |                                              |
             | <-X-- 5. Body HTML (segment 1448B) ----------| DROP   > 1000B, vứt bỏ âm thầm
             |   ^                                          |
             | MTU BLACKHOLE                                | không có ICMP Frag Needed
             |                                              | báo ngược về cho Server
             | <-X-- Retransmit 0.2s 0.4s 0.8s 1.6s --------| DROP   Server thử lại vô vọng
             v                                              |
   curl: HTTP 200  |  0 bytes  |  treo mãi mãi
```

> 🧪 **Ghi chú lab:** Ngưỡng chặn trong lab là **1000 bytes** (dễ quan sát), thực tế là MTU đường truyền 1400–1420 sau khi VPN/tunnel đóng thêm header. Luật DROP đặt ở phía **client** để Wireshark vẫn bắt được các gói Retransmission trước khi chúng bị vứt.

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-04-mtu-blackhole
docker compose up -d --build
```

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi MTU Blackhole:
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy chẩn đoán nhanh:
   ```bash
   ./scripts/test.sh
   ```

#### 🔍 Hiện tượng quan sát được:
1. **Ping nhỏ (64B):** Phản hồi cực nhanh, `0% packet loss`.
2. **Ping lớn kèm cờ Don't Fragment (`ping -s 1400 -M do`):** Mất gói `100%` (Request timed out)! Đây là **chiêu bắt bệnh MTU đỉnh cao** — chỉ một lệnh là khoanh vùng xong.
3. **Truy cập Web (`curl`):**
   ```
   curl: (28) Operation timed out after 8004 milliseconds with 0 out of 3093 bytes received
   HTTP 200 | tải về 0 bytes | 8.004639s
   ```
   Bắt tay TCP thành công, server **đã trả về `200 OK`**, nhưng body 3093 bytes không về được byte nào.

> 💡 **Điểm phân biệt với Tập 01 (Firewall DROP):** Ở tập 01, `curl` treo ngay từ `Connecting...`, không bao giờ có mã HTTP. Ở tập 04, `curl` báo `HTTP 200` rồi mới treo → chứng tỏ đường đi **thông ở gói nhỏ, tắc ở gói to**. Đó là dấu vân tay của bệnh MTU.

---

### Bước 3: Bắt mạch trên Wireshark

1. Bắt gói tin **trong container `client`** rồi mở bằng Wireshark (chạy được trên cả macOS/Windows — xem mục [🦈 Bắt gói tin bằng Wireshark](../README.md#-bắt-gói-tin-bằng-wireshark-trên-mọi-hệ-điều-hành) ở README series).
   ```bash
   docker compose exec -d client tcpdump -i eth0 -w /tmp/lab04.pcap -n "tcp port 80 or icmp"
   docker compose exec client curl -sS -o /dev/null --max-time 6 http://172.28.4.10
   docker compose exec client pkill tcpdump
   docker compose cp client:/tmp/lab04.pcap ./lab04.pcap
   ```
   > ⚠️ **Bắt ở client, KHÔNG bắt ở server.** Với gói do chính máy sinh ra, netfilter chạy *trước* packet tap — nếu vứt gói ở `OUTPUT` của server thì tcpdump hai đầu đều không thấy gì, mất sạch bằng chứng. Script `1-fault.sh` cố tình đặt luật ở `INPUT` của client để gói vào tới card mạng, được tcpdump ghi lại, rồi mới bị vứt.

2. Display filter:
   ```wireshark
   tcp.port == 80 || icmp
   ```

3. Soi gói tin — đây là những gì bạn sẽ thấy:
   * Bắt tay TCP `[SYN]` → `[SYN, ACK]` → `[ACK]` thành công.
   * Client gửi `GET /` (`Len=75`) thành công.
   * Server trả `HTTP/1.1 200 OK` (`Len=239`) — **về được**, vì nhỏ hơn 1000 bytes.
   * Sau đó server gửi body: `Len=1448` — và lặp đi lặp lại **`[TCP Retransmission]`** với backoff tăng dần (0.2s → 0.4s → 0.8s → 1.6s) vì không bao giờ nhận được ACK:
     ```
     172.28.4.10.80 > 172.28.4.20: seq 240:1688, length 1448
     172.28.4.10.80 > 172.28.4.20: seq 240:1688, length 1448   <-- Retransmission
     172.28.4.10.80 > 172.28.4.20: seq 240:1688, length 1448   <-- Retransmission
     172.28.4.10.80 > 172.28.4.20: seq 240:1688, length 1448   <-- Retransmission
     ```
   * **Tuyệt đối không có gói ICMP Type 3 Code 4** nào. Chính sự *vắng mặt* này mới là chẩn đoán — mạng đang "câm", không báo cho ai biết gói quá to.

> 🔧 **Vì sao `Len=1448` chứ không phải 1460?** MSS = 1460, nhưng TCP Timestamps chiếm 12 bytes option → payload thực còn 1448.
> 🔧 **Offload (GSO/TSO/GRO):** Script đã tự tắt (`ethtool -K eth0 tso off gso off` ở server, `gro off` ở client). Nếu quên tắt, kernel server đẩy nguyên khối 3093 bytes qua veth và Wireshark hiển thị một gói **`length 3093` không hề tồn tại trên dây thật** — học viên sẽ nhìn nhầm hoàn toàn kích thước segment.

---

### Bước 4: Khắc Phục Sự Cố (Fix & Remediate)

```bash
./scripts/2-fix.sh
```

> **Cách chữa của lab:** script **KHÔNG gỡ luật chặn gói lớn** — mô phỏng tình huống thực tế bạn không sửa được đường truyền nghẽn (VPN/tunnel/cloud của bên thứ ba). Thay vào đó nó kẹp MTU của route tới client xuống `940`:
> ```bash
> ip route replace 172.28.4.20/32 dev eth0 mtu 940
> ```
> Server tự tính MSS gửi đi `= 940 − 40 = 900 bytes`, nên mọi segment server→client tối đa ~940 bytes, **luôn nhỏ hơn ngưỡng 1000 bytes bị DROP** → Web tải trọn vẹn dù "đường ống" vẫn nghẽn.

> ⚠️ **Đây KHÔNG phải TCP MSS Clamping theo đúng nghĩa.** MSS Clamping thật (`iptables -t mangle ... -j TCPMSS --clamp-mss-to-pmtu`) chạy ở chain **`FORWARD`**, tức trên **router/firewall trung gian** sửa MSS của gói đi ngang qua. Ở lab này server là **endpoint**, không forward gói của ai cả — nên cách tương đương ở endpoint là kẹp MTU của route. Kết quả giống nhau (segment nhỏ lại), vị trí áp dụng khác nhau. Ngoài đời bạn sẽ dùng bản `FORWARD` ở mục đúc kết bên dưới.

Kiểm tra lại:
```bash
./scripts/test.sh
```
Trước khi chữa: `HTTP 200 | tải về 0 bytes` (curl treo 8s). Sau khi chữa: `HTTP 200 | tải về 3093 bytes` gần như tức thì (dưới 1s).

> 🚨 **Đừng hoảng: `ping -s 1400 -M do` VẪN rớt 100% sau khi chữa — và như vậy là ĐÚNG.** Route MTU chỉ điều khiển kích thước segment TCP; gói ICMP 1428 bytes vẫn đâm thẳng vào luật chặn. Đây chính là bài học cốt lõi của tập này: **ta né được chỗ nghẽn cho ứng dụng, chứ không chữa được đường ống**. Muốn "hết bệnh" thật sự thì phải sửa ở chỗ gây nghẽn (`docker compose exec client iptables -F`).

---

## 🧠 Bác Sĩ Mạng Đúc Kết: Giải Pháp Thực Tế Cho Lỗi MTU

1. **Nguyên nhân thực tế:** Thường xảy ra khi dữ liệu đi qua **VPN IPsec, GRE Tunnel, VXLAN, PPPoE** (các giao thức này đóng thêm Header làm giảm MTU khả dụng từ 1500 xuống 1400–1420).
2. **Đơn thuốc xử lý (Best Practices):**
   * **TCP MSS Clamping (khuyên dùng nhất — trên Router/Firewall):**
     ```bash
     iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
     ```
     👉 Router tự sửa giá trị MSS trong gói SYN đi ngang qua thành kích thước nhỏ an toàn.
   * **Trên endpoint (khi không đụng được vào router):** kẹp MTU của route/interface như `2-fix.sh` đã làm.
   * **Không bao giờ chặn ICMP Type 3 Code 4:** Mở Firewall cho phép gói ICMP thông báo "Fragmentation Needed" — đây mới là gốc rễ biến một đường truyền MTU thấp (bình thường, PMTUD tự xử lý được) thành một **blackhole**.

---

---

## 💡 Cơm Thêm: Mô Phỏng Thực Tế Với Router / Firewall Trung Gian

> 🚀 **Lab nâng cao (3 Nodes):** Bạn muốn thấy tận mắt gói `ICMP Type 3 Code 4` sinh ra từ Router, bị Firewall chặn tạo thành Blackhole, và cấu hình `TCP MSS Clamping` trên chain `FORWARD`?
> 👉 Xem tài liệu chuyên sâu: [**`com-them.md`**](./com-them.md) và thực hành với lab 3 nodes tại thư mục [**`com-them-router/`**](./com-them-router).

---

## 📝 Câu Hỏi Ôn Tập

1. Vì sao `ping` gói nhỏ chạy tốt, bắt tay TCP thành công, `curl` còn báo được `HTTP 200`, nhưng trang web vẫn đơ giữa chừng?
2. TCP MSS Clamping khắc phục lỗi này bằng cơ chế nào (mà không cần sửa "đường ống" nghẽn)? Vì sao ở lab này ta dùng `ip route ... mtu` thay vì `--clamp-mss-to-pmtu`?
3. Vì sao **tuyệt đối không** được chặn gói ICMP Type 3 Code 4?
4. Chữa xong Web tải ngon rồi, nhưng `ping -s 1400 -M do` vẫn rớt 100%. Vì sao? Lab đã thật sự "hết bệnh" chưa?

<details><summary>Gợi ý đáp án</summary>

1. Gói nhỏ (ping, SYN, HTTP header 239B) lọt qua; segment body 1448B vượt ngưỡng nghẽn bị DROP âm thầm, không có ICMP báo về nên không bên nào biết mà giảm kích thước → server retransmit vô vọng (PMTUD Blackhole).
2. Kẹp MSS/MTU để host chỉ gửi segment nhỏ hơn ngưỡng nghẽn — data không bao giờ chạm mức bị drop (lab đặt route MTU 940 → MSS 900). Dùng `ip route ... mtu` vì `--clamp-mss-to-pmtu` chạy ở chain `FORWARD` (dành cho router trung gian), còn server trong lab là endpoint chứ không forward gói.
3. ICMP Type 3 Code 4 ("Fragmentation Needed") là cách mạng báo "gói quá to, hãy giảm kích thước". Chặn nó = tắt cơ chế PMTUD → biến đường truyền MTU thấp (vốn vô hại) thành blackhole.
4. Vì route MTU chỉ ảnh hưởng segment TCP, còn gói ICMP 1428 bytes vẫn vượt ngưỡng chặn. Chưa hết bệnh — ta mới **né** chỗ nghẽn để ứng dụng chạy được. Chữa tận gốc phải sửa ở thiết bị gây nghẽn (nâng MTU, hoặc mở ICMP Frag Needed).
</details>

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```

