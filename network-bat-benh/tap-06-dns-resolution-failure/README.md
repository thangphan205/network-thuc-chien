# 🩺 Ca Bệnh 06: Ping IP Thì Mượt, Gõ Tên Miền Thì Chết — Bắt Bệnh DNS

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** `ping 172.28.6.10` và `curl http://172.28.6.10` chạy mượt. Nhưng gõ `curl http://web.lab.local` thì nhận `Could not resolve host` — hoặc tệ hơn: **vẫn ra HTTP 200, chỉ là từ nhầm máy**.
> * **Bản chất lỗi:** Sự cố ở **Tầng 7 — khâu phân giải tên**. Mọi thứ ở L2/L3/L4 đều đúng tuyệt đối.
> * **Chỗ khiến ca này khó lần:** "DNS lỗi" không phải một bệnh, nó là **tám bệnh khác nhau** dùng chung vài câu thông báo. `curl` trả về cùng một dòng `Could not resolve host` cho nhiều nguyên nhân trái ngược nhau. Và ba trong tám ca (KB6, KB7, KB8) **không hề báo lỗi gì cả** — chúng trả về HTTP 200 từ sai địa chỉ.

> 🧪 **Lab có DNS server thật (dnsmasq), không dùng resolver nhúng của Docker.** 8 kịch bản, gom thành 4 nhóm theo câu hỏi *"ai đang làm sai?"*:
>
> | Nhóm | KB | Ca | Chữ ký `dig` |
> | :-- | :-- | :--- | :--- |
> | — | KB1 | Khoẻ (mốc so sánh) | `NOERROR`, IP đúng |
> | **1. Server không đáp** | KB2 | Resolver không tới được (im lặng) | `timed out` ~2000 ms, log server 0 query |
> | | KB3 | Dịch vụ DNS chết (từ chối) | `connection refused` ~20 ms |
> | | KB4 | DNS local sống, upstream bị chặn | `timed out` ~2000 ms, log có `forwarded` mà không có trả lời |
> | **2. Server đáp "không có"** | KB5 | NXDOMAIN (gõ sai tên / thiếu bản ghi) | `NXDOMAIN` ~0 ms |
> | **3. Server đáp sai** | KB6 | Bản ghi A trỏ địa chỉ cũ | `NOERROR`, **IP sai**, HTTP 200 nhầm máy |
> | **4. Client chen ngang** | KB7 | `/etc/hosts` đè lên DNS | `NOERROR`, **IP đúng**, ứng dụng vẫn sai |
> | | KB8 | Bộ đệm giữ IP cũ | `NOERROR`, IP mới, ứng dụng vẫn dùng IP cũ |
>
> Số `KB1`–`KB8` đánh theo **thứ tự trình bày** và khớp tên script trong `scripts/` (`1-binh-thuong.sh` … `8-cache-cu.sh`).

> 📚 **Điều kiện tiên quyết:** Nắm `ping`, `curl`, `dig` ở mức cơ bản. Đây là ca bệnh **Tầng 7** đầu tiên của series.

---

## 🔬 Sơ đồ Kiến trúc Lab

![Sơ đồ kiến trúc lab tập 06](./images/so-do-kien-truc.png)

> 🖼️ **Bản HTML tương tác** — 8 tab KB1–KB8 theo thứ tự trình bày, mỗi tab một kịch bản, thấy ổ bệnh nằm ở chặng nào
> (`curl` → `/etc/hosts` → `nscd` → DNS, hay `dig` hỏi thẳng DNS):
> [`so-do-kien-truc.html`](./so-do-kien-truc.html)

* **`client` dùng glibc (Debian), không dùng musl (Alpine).** Resolver là một phần của libc — đổi libc là đổi hành vi. Xem [callout bên dưới](#-musl-vs-glibc--cùng-một-resolvconf-hai-kết-quả).
* **Client trỏ thẳng vào `172.28.6.53`, không dùng DNS nhúng `127.0.0.11` của Docker.** Nhờ vậy mọi hành vi phân giải nằm trong tầm kiểm soát của script, và **8 kịch bản chạy được cả khi máy bạn rút mạng**. DNS của lab có thêm upstream `8.8.8.8` / `1.1.1.1` chỉ để phân giải tên public (`docker exec lab06-client dig google.com`; `./scripts/xem-log-dns.sh` sẽ thấy `forwarded ... to 8.8.8.8`). Rút mạng thì chỉ tên public hỏng, `lab.local` vẫn bình thường.
* **`web-cu` là đích sai còn sống.** Nó tồn tại để dựng được ca nguy hiểm nhất: DNS trả lời trót lọt, HTTP 200, mà người dùng đang xem nhầm server.
* **`.99` là địa chỉ không có máy nào** — dùng cho ca "resolver không tới được" và "DNS trả về địa chỉ chết".

> 🔑 Cả tập gói trong một câu: **`dig` chạy tốt KHÔNG có nghĩa là DNS đúng.**

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Dựng lab

```bash
cd network-bat-benh/tap-06-dns-resolution-failure
./scripts/0-setup.sh
```

`0-setup.sh` **idempotent** — chạy lại bất cứ lúc nào để reset sạch. Nó dọn cả những thứ mà `docker compose restart` không dọn được: dòng thừa trong `/etc/hosts`, bộ đệm `nscd`, zone bị sửa, forwarder chết, `resolv.conf` bị trỏ sai.

> **Quy tắc bất di bất dịch: sau MỖI kịch bản, chạy lại `./scripts/0-setup.sh`.**

Ba terminal nên mở sẵn suốt buổi:

```bash
# Terminal 1 — chạy kịch bản
./scripts/0-setup.sh

# Terminal 2 — máy đo phía client (nạn nhân)
docker exec -it lab06-client monitor.sh

# Terminal 3 — góc nhìn phía DNS server (nơi phá án)
./scripts/xem-log-dns.sh
```

> ⚠️ **KHÔNG dùng `docker compose logs dns`** — nó bắt được **0 dòng**. dnsmasq được khởi động bằng `docker exec` nên không phải PID 1 của container; log nằm trong file. Dùng `./scripts/xem-log-dns.sh`.

---

### Bước 2: Chạy một ca bệnh và đọc chữ ký

```bash
./scripts/2-resolver-khong-toi-duoc.sh     # hoặc 1, 3 … 8
./scripts/test.sh                          # chẩn đoán 7 bước, tự luận giải
```

`test.sh` chạy được ở **bất kỳ trạng thái nào** của lab và tự chỉ ra kịch bản nào đang chạy.

> ⚠️ `test.sh` mặc định hỏi `web.lab.local`. Hai kịch bản hỏi **tên khác** — phải truyền tên, nếu không `test.sh` sẽ báo "khoẻ":
> * KB5: `./scripts/test.sh wed.lab.local`
> * KB4: `./scripts/test.sh db.noi-bo.local`
>
> Cuối output của hai script này đều in sẵn lệnh cần chạy.

---

### Bước 3: Bắt gói tin

```bash
./scripts/bat-goi-dns.sh 12                # 12 giây, xuất .pcap ra thư mục tập
```

Mở file `.pcap` bằng Wireshark, display filter: `dns || arp`

| Thấy gì trong Wireshark | Nghĩa là |
| :--- | :--- |
| Chỉ có **ARP** `who-has` lặp lại, **không có gói DNS** | Nameserver cùng subnet mà không ai trả lời ARP: gói UDP chưa từng lên dây — KB2 |
| Chỉ có `Standard query`, **không có** response | Gói đã lên dây mà không ai đáp — KB4 (hoặc firewall DROP thật) |
| `query response ... No such name` | NXDOMAIN — KB5 |
| `query response A 172.28.6.11` | Có trả lời, nhưng **sai IP** — KB6 |
| **Không có gói nào cả** | Ứng dụng chưa hề hỏi DNS — KB7 hoặc KB8 |

Bắt gói **trong container** nên chạy giống nhau trên macOS/Windows/Linux (xem [mục Wireshark ở README series](../README.md#-bắt-gói-tin-bằng-wireshark-trên-mọi-hệ-điều-hành)).

---

### Bước 4: Tự bắt bệnh — ca bí ẩn

Học xong KB2–KB8, tự kiểm tra tay nghề:

```bash
./scripts/ca-bi-an.sh                      # gieo ngẫu nhiên 1 ca trong KB2–KB8
```

Script dựng lab sạch, gieo **một ca ngẫu nhiên** lên tên miền mới `api.cua-hang.local` (không trùng tên nào trong các kịch bản, nên tên không gợi ý đáp án), rồi chỉ in **phiếu báo bệnh** — không in số ca, không in lời giải.

Việc của bạn:

1. Tìm ra ca bệnh bằng các công cụ đã học: `monitor.sh`, `dig`, `getent`, `curl -v`, `xem-log-dns.sh`, `bat-goi-dns.sh`. Nhớ truyền tên `api.cua-hang.local`.
2. Chữa **đúng chỗ** — trên client hay trên DNS server.
3. Tự kiểm: `docker exec lab06-client curl -s http://api.cua-hang.local/` phải ra trang **SERVER MỚI** từ `172.28.6.10`.

> `./scripts/test.sh api.cua-hang.local` là phao cứu sinh — chỉ dùng khi bí. **Đừng** chạy `0-setup.sh` để "chữa": nó xoá luôn vùng `cua-hang.local`. Chạy lại `ca-bi-an.sh` để chơi ván mới.

---

## 🧠 Bảng Vân Tay — Thứ Đáng Học Thuộc Nhất Tập Này

Toàn bộ số liệu dưới đây **đo trong chính lab này**, không phải con số tham khảo:

```
  dig                         curl       NSS vs dig    -> Ca bệnh
  --------------------------- ---------- ------------- --------------------------
  NOERROR, IP đúng            200        khớp          KHOẺ
  timed out (~2000 ms)        28 / 6 *   -             KB2 resolver không tới được
                                                       (log server: 0 query)
  connection refused (~20 ms) exit 6     -             KB3 dịch vụ DNS chết
  timed out (~2000 ms)        exit 6     -             KB4 DNS sống, upstream chết
                                                       (log: query + forwarded, KHÔNG có trả lời)
  NXDOMAIN (~0 ms)            exit 6     -             KB5 không có bản ghi
  NOERROR, IP SAI             200 / 28   khớp          KB6 DNS trả sai địa chỉ
  NOERROR, IP đúng            200        LỆCH          KB7 /etc/hosts đè lên
  NOERROR, IP mới             200        LỆCH (cũ)     KB8 bộ đệm giữ IP cũ
```

\* curl của lab đặt `--connect-timeout 3`. KB2 mất ~3,8 giây (glibc thử 2 tên, mỗi tên 2 giây) nên bị cắt ở exit 28; `curl` trần sẽ ra exit 6 như KB4. **Exit code không tách được KB2 khỏi KB4** — thời gian và log server mới tách được.

Ba cặp dễ nhầm nhất — và cách tách:

1. **KB3 vs KB5** — `curl` nói **y hệt** nhau: `curl: (6) Could not resolve host`. Nguyên nhân trái ngược (dịch vụ chết / bản ghi thiếu). **`curl` không đủ để chẩn đoán, phải `dig`.**
2. **KB2 vs KB4** — `dig` nói **y hệt** nhau: `timed out` sau ~2000 ms. Không lệnh nào chạy *trên client* tách được. **Chỉ log phía server trả lời được:** 0 query = gói chưa tới nơi (KB2); có query và `forwarded` mà **không có dòng trả lời** = gói tới nơi rồi, server không lấy được câu trả lời từ upstream (KB4). Ngoài đời đây là ca *"ping 8.8.8.8 được, tên ngoài chết, tên nội bộ vẫn 0 ms"*.
3. **KB6 vs KB7/KB8** — cả ba đều HTTP 200 từ nhầm máy. Tách bằng: `dig @<IP DNS thật>` và `getent hosts` có **lệch nhau** không. Khớp → lỗi ở DNS server (KB6). Lệch → thủ phạm nằm **trên máy client** (KB7 `/etc/hosts`, KB8 bộ đệm).

---

## 🧭 Quy Trình Debug DNS — 5 Bước, Đúng Thứ Tự

```
1. Loại trừ tầng dưới:   ping <IP đích>          -> thông = L3 OK, đừng soi mạng nữa.
2. Client đang hỏi ai:   resolvectl status        (Ubuntu 24.04+, xem dòng "DNS Servers")
                         cat /etc/resolv.conf     (thấy 127.0.0.53 = đang đi qua systemd-resolved)
3. ỨNG DỤNG dùng IP nào: getent hosts <tên>       <- đi ĐÚNG đường ứng dụng đi
4. DNS SERVER nói gì:    dig @<IP DNS thật> <tên> <- hỏi THẲNG server ở bước 2, vượt mọi lớp đệm
5. So bước 3 với bước 4: lệch  -> thủ phạm TRÊN MÁY CLIENT (hosts / nscd / systemd-resolved)
                         khớp  -> hỏi tiếp: IP đó có ĐÚNG không? (KB6)
```

> ⚠️ **Bước 3 là bước hay bị bỏ nhất và là bước quan trọng nhất.** `dig` **không** đọc `/etc/hosts`, **không** đi qua `nscd` — nhưng **có** đi qua `systemd-resolved` nếu `resolv.conf` trỏ `127.0.0.53`, nên bước 4 phải có `@<IP DNS thật>`. Nó nói cho bạn biết DNS server nghĩ gì — không phải ứng dụng của bạn đang làm gì. Ticket bị đóng nhầm với dòng "dig kiểm tra thấy bình thường" là ticket KB7 hoặc KB8.

> 🐧 **Ghi chú Ubuntu Server 24.04+** — Quy trình trên viết cho Ubuntu Server 24.04 trở về sau. Mặc định trên các bản này: `systemd-resolved` chạy sẵn, `/etc/resolv.conf` trỏ `nameserver 127.0.0.53`, còn `nscd` **không** được cài. Hệ quả:
> * `dig <tên>` không có `@` là hỏi `127.0.0.53` — tức hỏi **chính bộ đệm** của `systemd-resolved`, không phải DNS server. Nếu bộ đệm đang giữ IP cũ, bước 3 và bước 4 **khớp nhau** mà vẫn sai → bạn đổ oan cho DNS server.
> * Tìm IP DNS thật: `resolvectl status` (dòng `DNS Servers`), rồi `dig @<IP đó> <tên>`.
> * Xoá bộ đệm: `sudo resolvectl flush-caches` — tương đương `nscd -i hosts` của KB8.
> * Kiểm lại sau khi xoá: `resolvectl query <tên>`; xem bộ đệm: `resolvectl statistics`. Vẫn sai thì `sudo systemctl restart systemd-resolved`.
>
> 🪟 **Ghi chú Windows 10/11** — lớp đệm là dịch vụ *DNS Client* (`Dnscache`), không có `nscd` hay `getent`. PowerShell chạy bằng Administrator:
> * IP ứng dụng thấy (đọc cả `hosts` lẫn bộ đệm): `Resolve-DnsName <tên>` hoặc `ping <tên>`.
> * Xem bản ghi đang bị giữ và TTL còn lại: `Get-DnsClientCache -Entry <tên>`.
> * Xoá bộ đệm: `ipconfig /flushdns` hoặc `Clear-DnsClientCache` — tương đương `nscd -i hosts` của KB8.
> * Đối chứng vượt bộ đệm, như `dig @<IP>`: `nslookup <tên> <IP DNS thật>`.
>
> ⚠️ Xoá bộ đệm hệ điều hành chưa đủ nếu ứng dụng tự đệm riêng: Chrome (`chrome://net-internals/#dns` → Clear host cache), JVM (khởi động lại).
>
> Lab chạy client Debian 12 **không có** `systemd-resolved`: `resolv.conf` trỏ thẳng `172.28.6.53`, nên trong lab `dig <tên>` và `dig @172.28.6.53 <tên>` cho cùng kết quả. KB8 minh hoạ bộ đệm bằng `nscd`; trên Ubuntu thật, lớp đệm bạn gặp nhiều nhất là `systemd-resolved`.

Khi `dig` báo timeout, còn **một câu hỏi nữa** phải hỏi trước khi kết luận:

```
6. Gói tin có TỚI ĐƯỢC DNS server không?   -> xem log phía server (và tcpdump phía server)
   0 query                          -> sai địa chỉ nameserver / firewall chặn UDP 53 (KB2)
   query + forwarded, không trả lời -> resolver nhận rồi, upstream chết              (KB4)
   query + CÓ dòng trả lời          -> server đã đáp, gói VỀ bị chặn (firewall/rp_filter): không phải KB4
   Lưu ý: firewall DROP ngay trên DNS server cũng cho "0 query" dù gói đã tới -> phải tcpdump phía server.
```

---

## 🐧 musl vs glibc — Cùng Một `resolv.conf`, Hai Kết Quả

Resolver là một phần của libc. Đổi distro nền là đổi hành vi phân giải. Ba điều dưới đây **đã đo trong lab này**:

| | musl (Alpine) | glibc (Debian/Ubuntu/RHEL) |
| :--- | :--- | :--- |
| `/etc/hosts` đè DNS | Có | Có |
| Tôn trọng `/etc/nsswitch.conf` | **Không** — Alpine có ship file này nhưng musl bỏ qua nó | Có |
| Nhiều `nameserver`, cái đầu chết | Hỏi **song song** → trả lời sau **~0 ms** | Hỏi **lần lượt**, chờ hết timeout → **~3000 ms** |

👉 Dòng cuối là lý do một dịch vụ chuyển từ image Alpine sang Debian có thể "bỗng dưng chậm" mà **không ai đổi gì về mạng**. Lab này dùng glibc vì đó là thứ học viên gặp trên server thật.

---

## ⚠️ Bẫy Thực Địa: ICMP Rate Limit

Nếu bạn bắn `dig` liên tục nhiều lần trong một giây vào một cổng đã đóng, bạn sẽ thấy `connection refused` **thỉnh thoảng đổi thành** `timed out`.

Đó không phải bệnh đổi. Đó là `net.ipv4.icmp_ratelimit` của Linux — mặc định chỉ cho phát **1 gói ICMP unreachable mỗi giây**. Gói thứ 2 trở đi bị kernel nuốt, và "từ chối" trông y hệt "im lặng".

👉 Khi chẩn đoán, `dig` **thong thả từng lần một**. Bắn liên tục là tự làm nhiễu chính bằng chứng của mình.

---

## 🧹 Dọn dẹp Lab

```bash
docker compose down
```
