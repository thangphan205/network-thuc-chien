# 🐳 Lab Containerlab: Mô Phỏng Cụm HA Failover & Lỗ Hổng Bảng ARP (Cisco / Linux)

> 🎯 **Mục tiêu:**
> 1. Triển khai mô hình High Availability (HA) với **Containerlab (clab)** — giải pháp tự động hóa mạng dạng mã nguồn (Infrastructure as Code) siêu nhẹ, chạy trực tiếp trên Linux/Docker.
> 2. Mô phỏng đúng kiến trúc mạng doanh nghiệp: **Client khác subnet với Server qua Router trung gian**.
> 3. Hỗ trợ **2 chế độ chạy**:
>    * **Cisco IOL (`vrnetlab/cisco_iol:17.12.01`)**: Kiểm chứng hiện tượng router Cisco ôm cache ARP sai suốt **4 tiếng**.
>    * **Linux Router (100% Open-Source)**: Tự động chạy ngay trên bất kỳ máy Linux nào mà không cần image Cisco bản quyền.

> ✅ **Lab đã được kiểm chứng thực tế** trên Ubuntu 24.04 + Docker 29.6.2 + Containerlab 0.78.0, chạy trọn vẹn cả 2 topology (Cisco IOL và Linux router).


> 🔗 **Quan hệ với lab chính.** Lab này dùng **cùng sơ đồ IP với lab chính** ở
> [`../README.md`](../README.md): client `172.28.51.20`, node `172.28.52.11` /
> `172.28.52.12`, VIP `172.28.52.100`, router `172.28.51.254` / `172.28.52.254`,
> `virtual_router_id 51`, priority `110`/`100`, `auth_pass 9pingHA1`. Chuyển qua
> lại giữa hai lab không phải học lại sơ đồ.
>
> ⚠️ **Khác biệt có chủ ý:** lab này **không có tầng app `172.28.53.0/24`** —
> nginx chạy thẳng trên node HA, không qua HAProxy. Vì vậy nó **không tái hiện
> được kịch bản 11** (router chặn LB → backend, client nhận HTTP 503). Đổi lại,
> nó cho bạn thứ lab chính không thể có: hành vi thật của thiết bị mạng thật.

---

## 📦 Yêu Cầu Môi Trường

| Thành phần | Ghi chú |
| :--- | :--- |
| Docker | Đã cài và chạy được `docker build` |
| Containerlab | `>= 0.78.0` |
| `sudo` không mật khẩu | Containerlab cần quyền root để tạo netns/bridge |
| `sshpass` | **Chỉ cần cho topology Cisco IOL** — dùng để đọc `show ip arp` từ CLI router.<br>Cài: `sudo apt-get install -y sshpass` |
| Image `vrnetlab/cisco_iol:17.12.01` | **Chỉ cần cho topology Cisco IOL** |

> ℹ️ Linux bridge `br-server` **không cần tạo tay** — `scripts/deploy.sh` tự tạo và tự xoá khi `destroy.sh`.

---

## 🔬 Sơ Đồ Kiến Trúc Lab Containerlab

```text
+------------------------------+          +------------------------------+
|      CLIENT LAN (eth1)       |          |      SERVER LAN (eth1)       |
|        172.28.51.0/24        |          |        172.28.52.0/24        |
+------------------------------+          +------------------------------+
|                              |          |                              |
|  [client]                    |          |  [node-a]  .52.11  MASTER   |
|  IP: 172.28.51.20            |          |  [node-b]  .52.12  BACKUP   |
|  route: .52.0/24 via .51.254 |          |                              |
|                              |          |  VIP: 172.28.52.100          |
+---------------+--------------+          +---------------+--------------+
                |                                         |
                | Eth0/1 (IOL) | eth1 (Linux)             | br-server
     +----------v-----------------------------------------v----------+
     |                      ROUTER TRUNG GIAN                         |
     |   Cisco IOL: Ethernet0/1 + Ethernet0/2                         |
     |   Linux    : eth1 + eth2                                       |
     |                                                                |
     |   Client Gateway: 172.28.51.254                                |
     |   Server Gateway: 172.28.52.254                                |
     +----------------------------------------------------------------+
```

### 📋 Bảng Quy Hoạch Cổng & Địa Chỉ IP

| Node | Interface | Kết nối tới | Địa chỉ IP | Ghi chú |
| :--- | :--- | :--- | :--- | :--- |
| **`router`** | `Ethernet0/0` (IOL) | *(management)* | `192.168.55.254/24` | Containerlab tự quản lý — **không dùng làm data link** |
| | `Ethernet0/1` (hoặc `eth1`) | `client:eth1` | `172.28.51.254/24` | Gateway mạng Client |
| | `Ethernet0/2` (hoặc `eth2`) | `br-server:srv-rtr` | `172.28.52.254/24` | Gateway mạng Server |
| **`br-server`** | Linux Bridge | Switch ảo L2 | - | Kết nối Router và 2 Server |
| **`client`** | `eth1` | `router` | `172.28.51.20/24` | Route: `172.28.52.0/24 via 172.28.51.254` |
| **`node-a`** | `eth1` | `br-server:srv-na` | `172.28.52.11/24`<br>**VIP:** `172.28.52.100/24` | Node MASTER ban đầu (priority 110) |
| **`node-b`** | `eth1` | `br-server:srv-nb` | `172.28.52.12/24` | Node BACKUP nhận VIP khi failover (priority 100) |

---

## 🚀 Hướng Dẫn Triển Khai Nhanh

### Bước 1: Khởi động Lab

Có 2 tùy chọn topology tùy thuộc vào môi trường của bạn:

* **Cách 1: Sử dụng Cisco IOL (Khuyên dùng nếu có image `vrnetlab/cisco_iol`):**
  ```bash
  ./scripts/deploy.sh topology.clab.yml
  ```
* **Cách 2: Sử dụng Router Linux thuần (100% Open-source, chạy được ngay):**
  ```bash
  ./scripts/deploy.sh topology-linux.clab.yml
  ```

Script sẽ tự động:
1. Build image Docker `tap05-ha-node:latest` (Nginx, Keepalived, arping, tcpdump).
2. **Tạo Linux bridge `br-server`** và tắt IGMP snooping trên bridge (VRRP chạy trên multicast `224.0.0.18`).
3. Deploy topology bằng Containerlab.
4. **Kiểm tra lại 3 veth `srv-rtr` / `srv-na` / `srv-nb` đã gắn đúng vào bridge** — thiếu một link là đứt L2, hai server không thấy VRRP của nhau và cùng lên MASTER (split-brain).

> ⏱️ Chờ khoảng **5–30 giây** cho VRRP hội tụ (riêng Cisco IOL cần ~30s để IOS boot xong) trước khi chạy `test.sh`.

---

### Bước 2: Kiểm tra trạng thái bình thường (Baseline)

Chạy script chẩn đoán tự động:
```bash
./scripts/test.sh
```

**Kết quả bình thường:**
1. MAC của `node-a` và `node-b` hiển thị rõ ràng (kèm dạng Cisco `aabb.ccdd.eeff`).
2. VIP `172.28.52.100` đang nằm trên **Server 1**.
3. Bảng ARP trên Client **chỉ có Gateway 172.28.51.254**, hoàn toàn không biết VIP là ai.
4. Bảng ARP trên Router học **đúng** MAC của Server 1 → `✅ Router đang trỏ ĐÚNG MAC của Server 1.`
5. Client gọi VIP trả về:
   ```
   HTTP/1.1 200 OK
   X-Backend-Server: node-a-MASTER
   <h1>TOI LA NODE-A (MASTER)</h1>
   ```

---

### Bước 3: Mở Tool Giám Sát Liên Tục Trên Client

Mở một cửa sổ terminal riêng và truy cập vào container Client để chạy script đo đạc SLA:

```bash
# Topology Cisco IOL
docker exec -it clab-tap05_garp_ha-client /root/monitor.sh

# Topology Linux router
docker exec -it clab-tap05_garp_ha_linux-client /root/monitor.sh
```

> ⚠️ **Đừng dùng** `docker exec -it $(docker ps -q -f name=client) ...`. Filter `name=` của Docker khớp theo **chuỗi con**, nên nếu trên host còn lab khác có container tên `client-a`, `client-b`… bạn sẽ chui nhầm container. Các script trong lab này đã dùng regex khớp chính xác tiền tố `clab-tap05_garp_ha(_linux)?-`.

Màn hình sẽ in ra trạng thái HTTP, backend đang phục vụ, latency và Gateway MAC mỗi giây một lần:

```
TIME       | STATUS       | BACKEND                | LATENCY    | ARP GATEWAY
04:45:25   | SUCCESS      | node-a-MASTER         | 0.000861 s | GW MAC: aa:bb:cc:00:03:10
```

---

### Bước 4: Kích hoạt Ca Bệnh — Failover KHÔNG phát GARP

Mô phỏng trường hợp MASTER chết, BACKUP nhận VIP nhưng script tự chế **quên phát GARP**:
```bash
./scripts/1-fault.sh
```

**Quan sát ngay hiện tượng:**
1. **Trên màn hình `monitor.sh` của Client:** dòng trạng thái lập tức chuyển đỏ `BLACKHOLE TIMEOUT (28)` — gói HTTP bị treo vì Router vẫn forward frame vào MAC của Server 1 đã "chết".
2. **Chạy chẩn đoán:**
   ```bash
   ./scripts/test.sh
   ```
   * VIP đã nhảy sang Server 2.
   * Router vẫn ôm MAC cũ của Server 1 → `❌ Router đang ôm MAC CŨ`.
   * Client `curl` VIP → `curl: (28) Connection timed out`.
   * Chiều từ Server 2 ping ra `172.28.51.20` **thông 100%** → dấu vân tay **đứt một chiều**.
   * *Với Cisco IOL: entry sai này tồn tại tới 14400s (4 tiếng) nếu không có GARP.*

---

### Bước 5: Khắc Phục Sự Cố — Server 2 phát Gratuitous ARP

```bash
./scripts/2-fix-garp.sh
```

**Kết quả:**
* Router cập nhật ngay lập tức sang MAC của Server 2.
* `monitor.sh` trên Client lập tức xanh trở lại với header `X-Backend-Server: node-b-BACKUP`.

---

## 🆚 Đối Chứng: Failover ĐÚNG CHUẨN (keepalived tự phát GARP)

Để thấy rõ GARP đáng giá thế nào, hãy so sánh với một failover **không bị phá hoại** — cứ để keepalived làm đúng việc của nó:

```bash
# Deploy lại lab sạch, rồi chỉ đơn giản là hạ keepalived trên node-a
docker exec clab-tap05_garp_ha_linux-node-a pkill keepalived
```

Kết quả đo được trên client (mỗi giây một lần):

```
baseline: 200
>>> pkill keepalived on node-a
  t+1s  http=200  backend=node-b-BACKUP
  t+2s  http=200  backend=node-b-BACKUP
  t+3s  http=200  backend=node-b-BACKUP
```

**Downtime = 0.** Keepalived trên Server 2 lên MASTER và **tự phát GARP** ngay, router cập nhật MAC tức thì.

> 💡 **Bài học:** cùng một kịch bản "MASTER chết", chỉ khác ở chỗ **có phát GARP hay không**:
> * Có GARP → chuyển đổi mượt, người dùng không kịp nhận ra.
> * Không GARP → blackhole kéo dài tới **4 tiếng** trên router Cisco.
>
> Đây chính là lý do các script HA "tự chế" (dùng `ip addr add` rồi thôi) rất nguy hiểm trong môi trường production.

---

## 🧹 Dọn Dẹp Lab

```bash
./scripts/destroy.sh                            # mặc định topology.clab.yml
./scripts/destroy.sh topology-linux.clab.yml    # nếu dùng profile Linux
```
Script xoá toàn bộ container, mạng management **và** Linux bridge `br-server`.

---

## 🧨 Những Cái Bẫy Đã Gặp Khi Dựng Lab (và cách xử lý)

Đây là các lỗi thực tế đã gặp khi kiểm chứng lab trên server. Toàn bộ đã được xử lý sẵn trong repo — phần này để bạn hiểu **tại sao** cấu hình lại viết như vậy.

### 1. Containerlab không tự tạo Linux bridge
`kind: bridge` chỉ **gắn veth vào bridge có sẵn**. Thiếu bridge sẽ lỗi ngay:
```
ERROR Bridge "br-server" referenced in topology but does not exist
```
→ `deploy.sh` tự chạy `ip link add name br-server type bridge`.

### 2. Cisco IOL cấm dùng `Ethernet0/0` làm data link
```
ERROR Iol Node: "router". Management interface Ethernet0/0, e0/0 or eth0 is not allowed.
```
`Ethernet0/0` map sang `eth0` = cổng management. Data link phải bắt đầu từ **`Ethernet0/1`**.

### 3. `startup-config` đầy đủ sẽ **ghi đè** bootstrap của IOL → mất management
Dùng full config làm `Ethernet0/0` bị `administratively down`, mất luôn SSH vào router.
→ Đổi sang **partial config** (`config/router.partial.cfg`): Containerlab **nối thêm** vào sau config bootstrap thay vì thay thế. Sau khi sửa, router SSH được bằng `admin/admin`:
```bash
ssh admin@192.168.55.254   # -> show ip arp
```

### 4. Tên endpoint phía bridge bị trùng với interface có sẵn trên host
Đặt `br-server:eth1/eth2/eth3` thì tên veth tạo trên host là `eth1`, `eth2`, `eth3` — trùng với interface của lab khác đang chạy. Hậu quả: **chỉ 1 trong 3 veth được gắn vào bridge**, đứt L2, hai server không thấy VRRP của nhau và **cùng lên MASTER (split-brain)** — cả hai cùng giữ VIP.
→ Đổi thành tên riêng: `srv-rtr`, `srv-na`, `srv-nb`. `deploy.sh` còn kiểm tra lại và gắn bù nếu thiếu.

### 5. `ip route add default` luôn lỗi trong container
```
RTNETLINK answers: File exists
```
Node containerlab đã có default route qua `eth0` (management).
→ Chỉ thêm route tới subnet đối diện: `ip route add 172.28.51.0/24 via 172.28.52.254 dev eth1`.

### 6. `exec` của Containerlab **không chạy qua shell**
```yaml
- printf '<h1>...</h1>' > /var/www/html/index.html   # ❌ ghi ra stdout, KHÔNG tạo file
```
Dấu `>` bị truyền vào như một tham số bình thường.
→ Đưa `index.html` vào `binds` thay vì tạo bằng `exec`.

### 7. Nginx trên Alpine trả 404 cho mọi request
Site mặc định của Alpine cố tình `return 404` và root trỏ `/var/www/localhost/htdocs`.
→ Ghi đè `/etc/nginx/http.d/default.conf` (root `/var/www/html` + header `X-Backend-Server` mà `monitor.sh` đọc).

### 8. `chmod +x` trên bind-mount `:ro` luôn thất bại
```
chmod: changing permissions of '/etc/keepalived/check_nginx.sh': Read-only file system
```
Tệ hơn: file bind-mount mang UID của user host nên keepalived bật `enable_script_security` sẽ **tắt luôn health check**:
```
Unsafe permissions found for script '/etc/keepalived/check_nginx.sh' - disabling.
Disabling track script chk_nginx due to insecure
```
→ **Bake `check_nginx.sh` vào Dockerfile** (root:root, 0755), bỏ hẳn bind-mount.

### 9. Các keyword GARP đặt sai block trong `keepalived.conf`
```
(Line 12) Unknown keyword 'garp_master_delay'
```
`garp_master_delay` / `garp_master_repeat` / `garp_master_refresh` / `garp_master_refresh_repeat` thuộc **`vrrp_instance`**, không phải `global_defs`. (Bản dùng trong `global_defs` phải có tiền tố `vrrp_`.)

### 10. `auth_pass` của VRRPv2 tối đa 8 ký tự
```
Truncating auth_pass to 8 characters
```
→ Dùng mật khẩu ≤ 8 ký tự.

### 11. ⭐ Containerlab bật sẵn `ip_forward=1` → **che mất toàn bộ ca bệnh**
Đây là cái bẫy nguy hiểm nhất: node `kind: linux` mặc định có `net.ipv4.ip_forward=1`. Khi router gửi frame tới MAC cũ, **node-a (đã mất VIP) vẫn nhận rồi ĐỊNH TUYẾN GIÙM gói đó sang node-b**. Bắt gói thấy rõ:
```
node-a > broadcast: ARP Request who-has 172.28.52.100 tell 172.28.52.11
node-b > node-a  : ARP Reply   172.28.52.100 is-at <MAC node-b>
```
→ `curl` vẫn trả `200 OK`, blackhole **không bao giờ xảy ra**, bài lab mất sạch ý nghĩa.
→ Thêm `sysctl -w net.ipv4.ip_forward=0` cho cả `node-a`, `node-b`, `client`.

### 12. ⭐ `pkill keepalived` (SIGTERM) khiến BACKUP **tự phát GARP**
Khi nhận SIGTERM, keepalived tắt "lịch sự": nó phát một **VRRP advertisement priority = 0** để nhường quyền. Server 2 thấy priority 0 sẽ lên MASTER **ngay lập tức** (không chờ hết 3 chu kỳ advert) và tự phát GARP → bệnh tự khỏi trong ~0.5s.
→ `1-fault.sh` phải: **hạ keepalived trên node-b TRƯỚC**, rồi mới `pkill -9` (SIGKILL) node-a.

### 13. Router Linux có ARP cache quá ngắn
Linux làm mới ARP sau vài chục giây nên "bệnh" tự khỏi trước khi kịp quan sát.
→ `topology-linux.clab.yml` kéo dài cache trên cổng Server LAN cho giống Cisco (14400s):
```yaml
- sysctl -w net.ipv4.neigh.eth2.base_reachable_time_ms=14400000
- sysctl -w net.ipv4.neigh.eth2.gc_stale_time=14400
- sysctl -w net.ipv4.neigh.eth2.delay_first_probe_time=14400
```

### 14. `containerlab exec` không vào được CLI của Cisco IOL
```
OCI runtime exec failed: exec: "show": executable file not found in $PATH
```
`containerlab exec` bản chất là `docker exec`. IOS chạy bên trong tiến trình `iol.bin`, không phải shell.
→ Phải **SSH vào management IP**. IOL 17.x dùng thuật toán cũ nên cần bật lại:
```bash
sshpass -p admin ssh \
  -o KexAlgorithms=+diffie-hellman-group14-sha1 \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAuthentication=no \
  admin@192.168.55.254 "show ip arp"
```

### 15. Dò loại router bằng `/proc/net/arp` là sai
Container `cisco_iol` **cũng là container Linux** nên vẫn có `/proc/net/arp` (rỗng, vì stack IP nằm trong `iol.bin`) → dò kiểu này luôn cho ra bảng ARP rỗng.
→ Dò bằng label của Containerlab:
```bash
docker inspect -f '{{ index .Config.Labels "clab-node-kind" }}' <container>
```
