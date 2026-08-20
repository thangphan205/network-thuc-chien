# 🩺 Ca Bệnh 03: Bind Localhost — Đứng Tại Server Vào Được, Máy Khác Thì Không

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Kỹ sư SSH vào máy chủ và gõ `curl http://localhost` thì thấy website chạy `200 OK` ngon lành. Nhưng người dùng hoặc các máy khác trong cùng mạng gõ vào IP máy chủ (`http://172.28.3.10` hoặc IP LAN) thì bị báo lỗi **Connection refused**.
> * **Bản chất lỗi:** Ứng dụng/Web Server chỉ lắng nghe (bind) trên địa chỉ Loopback `127.0.0.1` thay vì lắng nghe trên tất cả các card mạng `0.0.0.0`.

> 📚 **Điều kiện tiên quyết:** Nắm được `curl`, `ss`, `tcpdump` ở mức cơ bản (xem series **Debug Mạng A-Z**) và đã học qua [Tập 02 — Firewall REJECT](../tap-02-firewall-reject) vì hai ca bệnh có **triệu chứng giống hệt nhau**.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER NETWORK                             |
|                                                                         |
|   [Client: 172.28.3.20]                      [Web Server: 172.28.3.10]  |
|            │                                             │              |
|            │ curl http://172.28.3.10:80                  │              |
|            │ (Gửi vào IP Card eth0)                      │              |
|            ▼                                             ▼              |
|   ┌──────────────────┐               ┌──────────────────────────────┐   |
|   │ Connection       │  <──(RST)──   │ Card eth0 (172.28.3.10):     │   |
|   │ Refused!         │               │ KHÔNG CÓ AI LẮNG NGHE!       │   |
|   └──────────────────┘               ├──────────────────────────────┤   |
|                                      │ Card lo (127.0.0.1):         │   |
|                                      │ Nginx chỉ lắng nghe ở đây!   │   |
|                                      │ (curl 127.0.0.1 -> 200 OK)   │   |
|                                      └──────────────────────────────┘   |
+-------------------------------------------------------------------------+
```

---

## 🚀 Hướng Dẫn Thực Hành

### Bước 1: Khởi động môi trường Lab
```bash
cd network-bat-benh/tap-03-bind-localhost
docker compose up -d --build
```

Kiểm tra các container đã sẵn sàng:
```bash
docker compose ps
```

> ⚠️ **Lưu ý reset:** Muốn đưa lab về trạng thái khỏe mạnh, chạy **`./scripts/0-reset.sh`** chứ **không** chạy lại `docker compose up -d`. Lý do: `up -d` có ghi lại file config đúng, nhưng thấy container không đổi nên không recreate — Nginx giữ nguyên socket `127.0.0.1:80` cũ. Kết quả là **file config nói đúng nhưng socket vẫn sai**, bạn đọc file để chẩn đoán sẽ ra kết luận ngược.

---

### Bước 2: Kích hoạt Ca Bệnh & Bắt mạch

1. Kích hoạt lỗi:
   ```bash
   ./scripts/1-fault.sh
   ```

2. Chạy chẩn đoán nhanh (4 bước tự động):
   ```bash
   ./scripts/test.sh
   ```

*(Hoặc chạy thủ công từng bước):*
```bash
# Bắt mạch tại chỗ: đứng TRONG server gọi loopback
docker compose exec web-server curl -I http://127.0.0.1

# Soi bảng socket: process đang bind vào địa chỉ nào?
docker compose exec web-server ss -tulpn | grep :80

# Bắt mạch từ xa: đứng từ máy khác gọi vào IP server
docker compose exec client curl -Iv http://172.28.3.10
```

#### 🔍 Hiện tượng quan sát được:

1. **Tại máy chủ:** `curl http://127.0.0.1` trả về `200 OK` — dịch vụ hoàn toàn sống.

2. **Soi bảng Socket (`ss -tulpn`):**
   ```
   Netid State  Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
   tcp   LISTEN 0      511        127.0.0.1:80         0.0.0.0:*    users:(("nginx",pid=1,fd=6))
   ```
   👉 Thấy rõ cột *Local Address* ghi đích danh `127.0.0.1:80` — **đây là bằng chứng kết tội**.

3. **Từ máy Client:** Gọi sang `172.28.3.10` bị `Connection refused` ngay lập tức (0 ms)!

4. **Bắt gói tin kiểm tra (tcpdump / Wireshark):**
   ```bash
   docker compose exec client tcpdump -i eth0 -n "tcp port 80"
   ```
   Mở terminal thứ 2 và bắn thử `docker compose exec client curl -m 3 http://172.28.3.10`, bạn sẽ thấy:
   ```
   172.28.3.20.52708 > 172.28.3.10.80: Flags [S],  seq 1230951860, ...
   172.28.3.10.80 > 172.28.3.20.52708: Flags [R.], seq 0, ack 1230951861, win 0
   ```
   👉 Client vừa gửi `[SYN]` thì Kernel của server lập tức bắn trả `[RST, ACK]` — vì gói tin đến card `eth0` mà **không có socket nào lắng nghe ở địa chỉ đó**. Chú ý `win 0`: đặc trưng của gói RST do kernel sinh ra.

> 🦈 **Mẹo soi bằng Wireshark (chạy được trên macOS/Windows):**
> ```bash
> # Bắt gói xuất ra file pcap trong container
> docker compose exec client tcpdump -i eth0 -n "tcp port 80" -w /tmp/cap03.pcap
>
> # Copy file ra máy host và mở bằng Wireshark
> docker compose cp client:/tmp/cap03.pcap ./cap03.pcap
> wireshark ./cap03.pcap
> ```
> *Display Filter gợi ý:* `tcp.flags.reset == 1`.

---

### Bước 3: Khắc Phục Sự Cố (Fix & Remediate)

Đổi cấu hình Nginx sang lắng nghe `0.0.0.0` (tất cả interfaces):
```bash
./scripts/2-fix.sh
```

Kiểm tra lại từ Client:
```bash
docker compose exec client curl -I http://172.28.3.10
```
Kết quả trả về **`HTTP/1.1 200 OK`**!

Soi lại bảng socket để thấy sự khác biệt:
```bash
docker compose exec web-server ss -tulpn | grep :80
# tcp LISTEN 0 511  0.0.0.0:80  0.0.0.0:*  users:(("nginx",pid=1,fd=6))
```

---

## 🧠 Phân Tích Kỹ Thuật: `127.0.0.1` vs `0.0.0.0`

| Cấu hình Bind | Ý nghĩa kỹ thuật | Khả năng truy cập từ ngoài |
| :--- | :--- | :--- |
| **`listen 127.0.0.1:80`** | Chỉ lắng nghe trên Loopback interface (`lo`). | ❌ **Chỉ nội bộ máy đó gọi được**, bên ngoài bị từ chối (Connection Refused). |
| **`listen 0.0.0.0:80`** (hoặc `listen 80`) | Lắng nghe trên **TẤT CẢ** các card mạng hiện có (Loopback, LAN, Public IP, Docker IP...). | ✅ **Mọi máy tính cùng mạng đều truy cập được**. |

> 💡 **Thực tế hay gặp:** Các framework backend (Flask, Django, Node.js Express, Spring Boot, FastAPI) khi chạy ở chế độ dev thường mặc định bind `127.0.0.1:8000` / `localhost:3000`. Khi deploy lên Docker/Kubernetes nếu không đổi thành `0.0.0.0` thì bên ngoài hoàn toàn không gọi vào container được!
>
> | Framework | Lệnh SAI (chỉ loopback) | Lệnh ĐÚNG khi containerize |
> | :--- | :--- | :--- |
> | Node.js Express | `app.listen(3000, 'localhost')` | `app.listen(3000, '0.0.0.0')` |
> | Python FastAPI | `uvicorn main:app --host 127.0.0.1` | `uvicorn main:app --host 0.0.0.0` |
> | Flask | `app.run()` (mặc định `127.0.0.1`) | `app.run(host='0.0.0.0')` |
> | Spring Boot | *(mặc định đã là `0.0.0.0`)* | `server.address=0.0.0.0` |

---

## ⚠️ Bẫy Chẩn Đoán: 3 Nguyên Nhân — 1 Triệu Chứng

Đây là phần **quan trọng nhất** của tập này. Cả ba trường hợp dưới đây đều trả về `TCP RST` và đều hiện lên màn hình đúng một dòng `Connection refused` trong 0 ms:

| # | Nguyên nhân | Ai bắn gói RST? |
| :-- | :--- | :--- |
| 1 | **Firewall REJECT** (`--reject-with tcp-reset`) — [Tập 02](../tap-02-firewall-reject) | iptables/nftables |
| 2 | **Process bind sai** vào `127.0.0.1` — Tập 03 (bài này) | Kernel (không có socket ở địa chỉ đó) |
| 3 | **Process chết hẳn** / chưa khởi động | Kernel (không có socket ở port đó) |

### 🧭 Cây quyết định phân biệt (chạy TRÊN SERVER)

```
                  ss -tulpn | grep :80
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
  (không có gì)      127.0.0.1:80         0.0.0.0:80
        │                  │                  │
        ▼                  ▼                  ▼
  Case 3:            Case 2:            Còn LISTEN mà ngoài
  Service chết       BIND SAI           vẫn refused ⇒ Case 1
        │            (bài này)                │
        ▼                  ▼                  ▼
  systemctl status   Sửa listen         iptables -L INPUT -n -v
  <service>          -> 0.0.0.0         (xem counter rule REJECT tăng)
```

> 🎯 **Quy tắc nhớ đời:** `Connection refused` **không** đồng nghĩa với "firewall chặn". Luôn chạy `ss -tulpn` **trước** khi đụng vào firewall — nếu không bạn sẽ ngồi debug iptables cả buổi trong khi lỗi nằm ở một dòng config của app.

---

## 🕳️ Bẫy phụ: Vì sao port `8083` trên máy host lại báo lỗi KHÁC?

Lab có publish port `8083:80`. Trong lúc đang bệnh, thử gọi từ máy host:

```bash
curl -I http://localhost:8083
# curl: (56) Recv failure: Connection reset by peer     ← KHÁC với trong container!
```

Trong container thì lỗi là `curl: (7) Connection refused`, nhưng qua host lại là `(56) Connection reset by peer`. Lý do: `docker-proxy` **nhận kết nối TCP thành công ở phía host trước**, sau đó mới thử nối tiếp vào container và bị RST — nên nó phải reset kết nối đã bắt tay xong với bạn.

👉 Bài học thực chiến: **mọi lớp proxy/NAT ở giữa (docker-proxy, Nginx reverse proxy, Load Balancer, Ingress) đều bóp méo triệu chứng gốc.** Muốn chẩn đoán chính xác, phải test từ vị trí gần server nhất có thể — đúng L3 của nó, không qua proxy.

---

## 📝 Câu Hỏi Ôn Tập

1. Vì sao đứng **tại server** curl `127.0.0.1` được, nhưng máy khác gọi vào IP server thì "Connection refused"?
2. Lệnh nào cho thấy tiến trình đang lắng nghe trên địa chỉ nào (`127.0.0.1` hay `0.0.0.0`)?
3. Sửa lỗi này bằng cách đổi `listen` thành gì?
4. Client nhận `Connection refused`. Chỉ với thông tin đó, có kết luận được là do firewall chặn không? Nêu quy trình 2 bước để phân biệt.
5. Trong lúc đang bệnh, gọi từ máy host vào `localhost:8083` lại ra `Connection reset by peer` thay vì `Connection refused`. Ai đã làm thay đổi triệu chứng?

<details><summary>Gợi ý đáp án</summary>

1. Nginx bind vào `127.0.0.1` (loopback) nên chỉ nhận kết nối từ chính máy đó; gói từ ngoài đi vào card `eth0` không có socket nào lắng nghe → kernel bắn `RST` → refused.
2. `ss -tulpn` (hoặc `netstat -tulpn`). Cột `Local Address` là `127.0.0.1:80` khi lỗi, `0.0.0.0:80` khi đúng.
3. `listen 80;` (tương đương `0.0.0.0:80`) để nghe trên mọi card mạng.
4. **Không.** Cả 3 nguyên nhân (firewall REJECT / bind sai / service chết) đều cho cùng triệu chứng đó. Quy trình: **Bước 1** — chạy `ss -tulpn | grep :80` trên server: không có gì = service chết; ra `127.0.0.1:80` = bind sai. **Bước 2** — nếu ra `0.0.0.0:80` mà ngoài vẫn refused thì mới chạy `iptables -L INPUT -n -v` xem counter của rule `REJECT` có tăng không.
5. `docker-proxy` (lớp NAT/proxy của Docker publish port). Nó đã hoàn tất bắt tay TCP với bạn ở phía host rồi mới bị container từ chối, nên buộc phải reset kết nối đang mở — đổi `refused` thành `reset by peer`.
</details>

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
