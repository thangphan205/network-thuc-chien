# 🩺 Ca Bệnh 08: Asymmetric Routing — Ping Thông 2 Chiều Nhưng Không Vào Được Web/SSH

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Từ client `ping` server: 0% loss. Từ server `ping` ngược lại: 0% loss. Nhưng mở SSH hoặc Web thì đứng im, rớt ngay từ bước bắt tay.
> * **Bản chất lỗi:** **Định tuyến bất đối xứng (Asymmetric Routing) gặp thiết bị stateful.** Gói `SYN` đi qua Firewall A (tạo session), gói `SYN-ACK` về theo tuyến khác qua Firewall B. B chưa từng thấy `SYN` nên coi gói là `INVALID` và DROP.
> * **Chỗ khiến ca này khó lần:** Bất đối xứng **tự nó không phải lỗi** — Internet chạy như vậy. Lỗi chỉ xuất hiện khi có **thiết bị giữ trạng thái** trên một trong hai đường, và **firewall bạn thấy DROP chưa chắc là firewall cần sửa**.

> 🧪 **Buổi học chỉ cần 2 ca chính — bệnh và thuốc:**
>
> | KB | Ca | `curl` | Ý nghĩa |
> | :-- | :--- | :--: | :--- |
> | KB1 | Khoẻ (mốc so sánh) | 200 | đường về đối xứng |
> | **KB2** | **Bất đối xứng + 2 firewall stateful** | **000** | `ping` thông, SYN-ACK về lệch đường bị DROP là gói INVALID |
> | **KB3** | **Chữa bằng SNAT tại fw-a** | 200 | ép đường về đi qua firewall đã thấy SYN |
>
> 📂 Các ca khác (chỉ cần một firewall stateful, hai bên stateless, `loose=1`, route đổi giữa phiên, sửa route tận gốc) vẫn chạy được, nằm trong [`scripts/mo-rong/`](./scripts/mo-rong/) — để học tiếp, không nằm trong luồng chính.
>
> 👉 Chi tiết từng kịch bản: [**kich-ban.md**](./kich-ban.md)

---

## 🔬 Sơ đồ Kiến trúc Lab

```text
                     +----[ fw-a  .251 | .251 ]----+
   LAN client        |   stateful, conntrack riêng  |        LAN server
   172.28.8.0/24 ---+                              +--- 172.28.18.0/24
   client .20        |                              |        server .10
                     +----[ fw-b  .252 | .252 ]----+
                         stateful, conntrack riêng

   SYN      : client --> fw-a --> server              (route tĩnh trên client)
   SYN-ACK  : server --> fw-a (khoẻ)  |  fw-b (BỆNH)  (route tĩnh trên server)
```

* **Hai router stateful THẬT.** Bản cũ của tập này chỉ có 1 server tự chặn `SYN-ACK` bằng iptables — tái hiện được *triệu chứng* chứ không phải *cơ chế*. Bản này dựng đúng hai firewall, mỗi cái giữ bảng conntrack **riêng**, không đồng bộ.
* **Ổ bệnh là một dòng route trên server** (`ip route replace 172.28.8.0/24 via <fw-a|fw-b>`). `0-setup.sh` đặt lại mỗi lần vì `ip route` chỉ sống trong netns đang chạy.
* Cả hai firewall chạy `privileged` để ghi sysctl `net.netfilter.*` trong netns của chúng (bắt buộc trên Docker Desktop).

> 🔑 Cả tập gói trong một câu: **"firewall nào DROP" chưa phải bằng chứng "firewall đó cần sửa" — hỏi tiếp: đường đi và đường về có cùng đi qua thiết bị giữ trạng thái đó không?**

---

## 🚀 Hướng Dẫn Thực Hành

```bash
cd network-bat-benh/tap-08-asymmetric-routing
./scripts/0-setup.sh                      # dựng lab + khẳng định trạng thái khoẻ
./scripts/xem-firewall.sh                 # terminal 2: bảng conntrack + counter INVALID của cả hai firewall
./scripts/2-bat-doi-xung-stateful.sh      # ⭐ ca bệnh chính
./scripts/3-chua-snat.sh                  # ⭐ chữa bằng SNAT → curl 200
./scripts/test.sh                         # chạy cả 8 KB (kể cả ca mở rộng), tự khẳng định chữ ký
```

> **Quy tắc bất di bất dịch: sau MỖI kịch bản, chạy lại `./scripts/0-setup.sh`.**
>
> 👉 **Chạy KB2 rồi MR1 liền nhau.** `curl` giữ nguyên 000; chỉ có **counter INVALID nhảy từ fw-b sang fw-a**.

---

## 🧠 Bảng Vân Tay — Thứ Đáng Học Thuộc Nhất Tập Này

Toàn bộ số liệu **đo trong chính lab này**:

| KB | Kịch bản | fw-a | fw-b | `ping` | `curl` | INVALID bị DROP ở |
| :-- | :--- | :--: | :--: | :--: | :--: | :--- |
| KB1 | đối xứng | stateful | stateful | thông | 200 | — |
| KB2 | **bất đối xứng** | stateful | stateful | thông | **000** | **fw-b** |
| KB3 | + SNAT tại fw-a | +NAT | stateful | thông | 200 | — |
| MR1 | fw-b thoáng | stateful | permissive | thông | **000** | **fw-a** |
| MR2 | hai bên stateless | permissive | permissive | thông | **200** | — |
| MR3 | `tcp_loose=1` | loose | loose | thông | **000** | cả hai |
| MR4 | route đổi giữa phiên | stateful | stateful | thông | GET #2 ❌ | **fw-b** |
| MR5 | sửa route | stateful | stateful | thông | 200 | — |

**Ba điều dễ nhầm:**

1. **KB2 vs MR1** — `curl` y hệt (000). Thủ phạm nhìn như đổi chỗ: fw-b DROP SYN-ACK; sau khi cho fw-b thoáng, fw-a DROP ACK vì chưa thấy SYN-ACK. **Một thiết bị stateful trên một đường là đủ chết.**
2. **MR2** — đường về vẫn lệch mà `curl` 200. Bất đối xứng không phải lỗi; **thiết bị stateful mới là điều kiện.**
3. **MR3 vs tập 07 MR1** — cùng `tcp_loose=1`: ở tập 07 nó "cứu" ca idle, ở đây **không cứu được gì**. Phải hiểu cơ chế, không học thuộc mẹo.

---

## 🧭 Quy Trình Debug — 4 Bước

```
1. Ping thông, TCP chết:   ping <host> ; curl -v <host>          -> nghi bất đối xứng + stateful
2. Đường đi VÀ đường về:   (client) traceroute <host>            -> đường đi
                           (server) traceroute <client>          -> đường về  (hai hop khác nhau = bất đối xứng)
3. Ai giữ trạng thái:      conntrack -L trên MỌI thiết bị trên CẢ HAI đường
                           SYN_SENT [UNREPLIED] = thấy SYN, không thấy SYN-ACK
                           counter INVALID tăng  = nhận gói của phiên chưa từng thấy
4. Chữa:                   sửa route (gốc)  >  SNAT (che)  >  đồng bộ state giữa hai firewall
```

> ⚠️ **Bước 2 phải làm từ CẢ HAI đầu.** `traceroute` chỉ từ client chỉ cho thấy đường đi — đường về là thứ bị lệch.

---

## 🩹 Ba Cách Chữa

1. **Sửa route (gốc)** — đường về đi qua **cùng** firewall với đường đi (MR5).
2. **SNAT tại Firewall A** (KB3) — server thấy nguồn là A nên trả lời về A. **Cái giá:** server mất IP thật của client (log, ACL, rate-limit theo IP đều sai).
3. **Cluster Active/Active có đồng bộ state** — nếu bắt buộc chạy hai firewall song song, phải đồng bộ bảng session (`conntrackd`, HA pair). **Không có cách "nới luật" nào thay thế.**

---

## 📋 Bảng Script

| Script | Việc |
| :--- | :--- |
| `0-setup.sh` | Reset lab về trạng thái khoẻ. Chạy sau mỗi kịch bản. |
| `1-binh-thuong.sh`, `2-bat-doi-xung-stateful.sh`, `3-chua-snat.sh` | 3 kịch bản luồng chính |
| `mo-rong/3,4,5,6,8-….sh` | 5 ca mở rộng — xem [kich-ban.md](./kich-ban.md) |
| `xem-firewall.sh` | Góc nhìn hai firewall (terminal 2) |
| `test.sh` | Chạy cả 8 kịch bản (kể cả ca mở rộng), khẳng định từng chữ ký |
| `lib.sh` | Hằng số + hàm dùng chung |

---

## 📝 Câu Hỏi Ôn Tập

1. `ping` thông hai chiều nhưng `curl` timeout. Bạn được gõ hai lệnh để phân biệt "firewall chặn" với "bất đối xứng". Đó là gì?
2. Bạn cho firewall đang DROP `INVALID` thoáng ra mà `curl` vẫn timeout. Chuyện gì đang xảy ra?
3. Đường về lệch nhưng `curl` 200. Hai điều kiện nào phải cùng đúng thì mới thành ca bệnh?
4. Vì sao SNAT chữa được nhưng không phải là chữa gốc? Cái giá là gì?
5. Vì sao `tcp_loose=1` cứu được ca idle timeout (tập 07) mà không cứu được ca này?

---

## 🧹 Dọn dẹp Lab

```bash
docker compose down -v
```
