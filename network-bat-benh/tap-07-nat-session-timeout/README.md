# 🩺 Ca Bệnh 07: NAT Session Timeout — Kết Nối Cứ Sau Vài Phút Không Dùng Là Đứt

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Ứng dụng kết nối Database (Connection Pool), SSH session hoặc WebSocket chạy ổn định khi liên tục có dữ liệu. Nhưng để máy nghỉ (idle) vài phút, khi gõ lệnh tiếp theo thì màn hình đơ cứng vài chục giây rồi báo **`Connection reset by peer`** hoặc **`Broken pipe`**.
> * **Bản chất lỗi:** **NAT / Stateful Firewall Session Idle Timeout ở Tầng 4.** Thiết bị trung gian (AWS NAT Gateway, Cisco, Fortinet…) giữ một **bảng conntrack**, mỗi dòng là một phiên và mỗi dòng có **đồng hồ riêng**. Không thấy gói nào trong X giây → dòng bị **xoá khỏi bảng**, không báo cho ai.
> * **Chỗ khiến ca này khó lần:** "Đứt sau idle" **không phải một bệnh**. NAT xoá phiên và **server tự đóng kết nối** cho ra **cùng một triệu chứng** (`1/2` phản hồi) nhưng thủ phạm hoàn toàn khác nhau. Và cùng một cú "hết hạn", TCP và UDP có **ba số phận khác nhau**.

> 🧪 **Buổi học chỉ cần 2 ca chính — bệnh và thuốc:**
>
> | KB | Ca | 2 GET / idle 7s | Ý nghĩa |
> | :-- | :--- | :--: | :--- |
> | KB1 | Khoẻ (mốc so sánh) | 2/2 | — |
> | **KB2** | **NAT xoá phiên, im lặng** | **1/2** | gateway DROP hẳn, không một gói RST |
> | **KB3** | **TCP keepalive chữa đúng** | 2/2 | chữa bằng cách giữ phiên "sống" trước khi NAT xoá |
>
> 📂 Các ca khác (NAT "tha" gói giữa chừng, UDP tự làm mới, server tự đóng, keepalive sai liều) vẫn chạy được, nằm trong [`scripts/mo-rong/`](./scripts/mo-rong/) — để học tiếp, không nằm trong luồng chính.
>
> 👉 Chi tiết từng kịch bản: [**kich-ban.md**](./kich-ban.md)

---

## 🔬 Sơ đồ Kiến trúc Lab

```text
   LAN client 172.28.7.0/24        WAN server 172.28.17.0/24

  +-----------+     +-----------------------------+     +-----------+
  | client    |     |  gateway  (NAT that)        |     | server    |
  | .20       |---->| .254 lan     .254 wan       |---->| .10       |
  | nc socat  |     |  ip_forward + MASQUERADE    |     | nginx :80 |
  | tcpdump   |<----|  conntrack  <-- O BENH      |<----| udp echo:9|
  +-----------+     +-----------------------------+     +-----------+
```

* **Gateway là một container riêng, không phải server.** Ngoài đời NAT/firewall là **thiết bị thứ ba** — client và server không biết gì về chuyện nó xoá phiên. Bản cũ của tập này để server tự đóng vai firewall; bản này tách ra đúng như thực tế.
* **Mọi số liệu conntrack nằm ở gateway** (`nf_conntrack_tcp_timeout_established`, `tcp_loose`, `udp_timeout`). Gateway chạy `privileged` để ghi được sysctl `net.netfilter.*` trong netns của nó (bắt buộc trên Docker Desktop).
* **Timeout ép xuống 5 giây** để demo nhanh; ngoài đời là 350s (AWS NAT Gateway) đến vài giờ. Cơ chế giống hệt.
* **Route tĩnh đặt lại mỗi lần `0-setup.sh`** vì `ip route` chỉ sống trong netns đang chạy (giống tập 05).

> 🔑 Cả tập gói trong một câu: **"đứt sau idle" chưa nói gì về thủ phạm — phải hỏi tiếp: có gói FIN không, và entry conntrack còn hay mất?**

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Dựng lab

```bash
cd network-bat-benh/tap-07-nat-session-timeout
./scripts/0-setup.sh
```

`0-setup.sh` **idempotent** — chạy lại bất cứ lúc nào để reset sạch, và **tự khẳng định** trạng thái khoẻ (2/2) trước khi trả quyền cho bạn.

> **Quy tắc bất di bất dịch: sau MỖI kịch bản, chạy lại `./scripts/0-setup.sh`.**

Hai terminal nên mở sẵn:

```bash
# Terminal 1 — chạy kịch bản
./scripts/2-nat-xoa-im-lang.sh

# Terminal 2 — góc nhìn bảng conntrack của gateway (nơi phá án)
./scripts/xem-conntrack.sh
```

### Bước 2: Chạy một ca bệnh và đọc chữ ký

```bash
./scripts/1-binh-thuong.sh          # mốc so sánh: 2/2
./scripts/2-nat-xoa-im-lang.sh      # ⭐ NAT xoá phiên          → 1/2, im lặng
./scripts/3-keepalive-cuu-song.sh    # ⭐ chữa đúng: TCP keepalive → 2/2
./scripts/test.sh                   # chạy cả 7 KB (kể cả ca mở rộng), tự khẳng định chữ ký
```

> 👉 **Chạy KB2 rồi MR3 liền nhau.** Toàn bộ bài học nằm ở chỗ con số trên màn hình **giống hệt** (1/2) còn thủ phạm thì trái ngược.

> ⚠️ Các phép thử đều tốn thời gian thật (idle 7 giây + chờ timeout của client). `test.sh` chạy vài phút — bình thường.

---

## 🧠 Bảng Vân Tay — Thứ Đáng Học Thuộc Nhất Tập Này

Toàn bộ số liệu dưới đây **đo trong chính lab này**:

| KB | Kịch bản | established timeout | loose | **2 GET / idle** | Thủ phạm | Chữa |
| :-- | :--- | :--: | :--: | :--: | :--- | :--- |
| KB1 | mặc định kernel | 432000s | 0 | 2/2 | — | — |
| KB2 | **NAT xoá phiên** | 5s | 0 | **1/2** | **GATEWAY** | TCP keepalive (KB3) |
| KB3 | keepalive đúng liều | 5s | 0 | 2/2 | — | (là thuốc) |
| MR1 | NAT "tha" giữa chừng | 5s | **1** | **2/2** | may rủi | keepalive, không dựa vào loose |
| MR2 | UDP hết hạn | udp 5s | — | 8/8 byte | — (tự làm mới) | — |
| MR3 | **server tự đóng** | 432000s | 0 | **1/2** | **SERVER** | tăng `keepalive_timeout` |
| MR4 | keepalive sai liều | 5s | 0 | 1/2 | cấu hình | `keepidle` < timeout NAT |

Cặp dễ nhầm nhất — và cách tách:

| | KB2 (NAT xoá) | MR3 (server tự đóng) |
| :--- | :--- | :--- |
| Gói tin lúc đóng | **KHÔNG CÓ GÌ** | **CÓ FIN** đúng giao thức |
| conntrack sau đó | entry **biến mất** | entry còn, `state=CLOSE` |
| Client | chờ hết **timeout riêng** | đóng **ngay** |

**Ba số phận của một phiên hết hạn:**

* **TCP, `loose=0`** → gói kế tiếp là `INVALID` → **DROP im lặng** (KB2).
* **TCP, `loose=1`** → kernel "nhặt" gói vào làm entry mới → **vẫn sống**, nhưng chỉ khi cổng dịch cũ còn trống — **may rủi, không phải thuốc** (MR1).
* **UDP** → không có khái niệm `INVALID`; gói kế tiếp thành `NEW` và được NAT lại, thường **cùng cổng** → ứng dụng **không hề biết** (MR2).

---

## 🧭 Quy Trình Debug "Đứt Sau Idle" — 4 Bước, Đúng Thứ Tự

```
1. Đứt sau bao lâu idle?        -> con số đó so với: timeout NAT/firewall? keepalive_timeout của server?
2. Có gói FIN/RST không?        -> tcpdump ở CẢ HAI đầu: có FIN = ứng dụng/server đóng (MR3)
                                                          im lặng  = NAT/firewall xoá (KB2)
3. Entry conntrack còn không?   -> conntrack -L trên gateway: còn (CLOSE) hay biến mất?
4. Đã bật keepalive chưa?       -> nếu rồi: keepidle có NHỎ HƠN timeout NAT không? (MR4)
```

> ⚠️ **Bước 2 là bước hay bị bỏ nhất.** Nghe "đứt sau idle" là nghĩ ngay đến NAT rồi đi chỉnh sysctl — trong khi thủ phạm là `keepalive_timeout` của nginx.

---

## 🩹 Ba Đơn Thuốc (đã verify bằng KB3/MR4)

1. **TCP Keepalive ở tầng ứng dụng / Database Pool** — `keepalive: true`, interval **nhỏ hơn** timeout của gateway (HikariCP, SQLAlchemy, GORM, Knex).
2. **SSH client** — `~/.ssh/config`:
   ```ssh
   Host *
       ServerAliveInterval 60
       ServerAliveCountMax 3
   ```
3. **Linux kernel (toàn máy)**:
   ```bash
   sysctl -w net.ipv4.tcp_keepalive_time=60
   sysctl -w net.ipv4.tcp_keepalive_intvl=10
   sysctl -w net.ipv4.tcp_keepalive_probes=3
   ```

> ⚠️ **Liều lượng quyết định tất cả** (MR4): bật keepalive nhưng `keepidle` lớn hơn timeout NAT thì vẫn chết y như không bật. Ngoài đời bạn thường không biết con số của NAT — đặt 30–60 giây là an toàn với hầu hết thiết bị.
>
> `tcp_keepalive_*` chỉ áp dụng cho socket **có bật `SO_KEEPALIVE`**. Bật sysctl mà ứng dụng không bật option trên socket thì không có tác dụng.

---

## 📋 Bảng Script

| Script | Việc |
| :--- | :--- |
| `0-setup.sh` | Reset lab về trạng thái khoẻ. Chạy sau mỗi kịch bản. |
| `1-binh-thuong.sh`, `2-nat-xoa-im-lang.sh`, `3-keepalive-cuu-song.sh` | 3 kịch bản luồng chính |
| `mo-rong/3,4,5,7-….sh` | 4 ca mở rộng — xem [kich-ban.md](./kich-ban.md) |
| `xem-conntrack.sh` | Góc nhìn bảng conntrack của gateway (terminal 2) |
| `test.sh` | Chạy cả 7 kịch bản (kể cả ca mở rộng), khẳng định từng chữ ký |
| `lib.sh` | Hằng số + hàm dùng chung |

---

## 📝 Câu Hỏi Ôn Tập

1. Ứng dụng báo `Broken pipe` sau khi idle. Bạn được gõ **một** lệnh để biết thủ phạm là NAT hay server. Lệnh đó là gì và bạn đọc gì?
2. Vì sao cùng một NAT timeout ngắn, TCP đứt còn UDP lại "vẫn chạy"?
3. `tcp_loose=1` làm ca bệnh biến mất. Có nên bật nó trên production không? Vì sao?
4. Đã bật keepalive mà vẫn đứt. Bạn kiểm tra điều gì đầu tiên?
5. Bạn không có quyền vào NAT Gateway của nhà mạng. Kể ra cách chữa bạn **có thể** làm.

---

## 🧹 Dọn dẹp Lab

```bash
docker compose down -v
```
