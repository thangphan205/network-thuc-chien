# 🩺 Ca Bệnh 04: Path MTU Blackhole — Ping Gói Nhỏ OK, Web Tải Nửa Chừng Thì Đơ

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Người dùng ping máy chủ thấy cực kỳ mượt mà. Mở website thì thấy tiêu đề trang vừa hiện lên nhưng sau đó trang web **quay vòng vòng vô tận** hoặc tải đơ nửa chừng.
> * **Bản chất lỗi:** **Path MTU Discovery (PMTUD) Blackhole**. Gói tin kích thước nhỏ (Ping 64B, TCP SYN 60B) đi qua thông suốt, nhưng khi Server gửi gói dữ liệu HTML/TLS lớn (> MTU của đường truyền), gói tin bị Router trung gian âm thầm hủy (DROP) do có cờ `DF (Don't Fragment)` mà không có thông báo ICMP Fragmentation Needed gửi về.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
+-------------------------------------------------------------------------+
|                              DOCKER NETWORK                             |
|                                                                         |
|   [Client: 172.28.4.20]                      [Web Server: 172.28.4.10]  |
|            │                                             │              |
|            │ 1. ping 64B (ICMP nhỏ) ──────────────────> │ [PASS ✓]     |
|            │ 2. TCP SYN (60B) ────────────────────────> │ [PASS ✓]     |
|            │ 3. GET / (Yêu cầu Web) ──────────────────> │ [PASS ✓]     |
|            │                                             │              |
|            │ <── 4. Trả về HTML to (> 1500B, cờ DF) ────┤              |
|            │               ▼                             │              |
|            │        [MTU BLACKHOLE]                      │              |
|            │   (Gói tin to bị vứt bỏ âm thầm)            │              |
|            │                                             │              |
|            │ <── Server gửi lại liên tục [Retransmission] ──────────────┤
|            ▼                                                            |
|   (Client đơ mãi mãi)                                                   |
+-------------------------------------------------------------------------+
```

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
1. **Ping nhỏ (64B):** Phản hồi cực nhanh 0% loss.
2. **Ping lớn với cờ Don't Fragment (`ping -s 1400 -M do`):** Bị mất gói 100% (Request timed out)!
3. **Truy cập Web (`curl`):** Kết nối TCP thành công (thấy dòng `Connected`), gửi `GET /` thành công, nhưng sau đó đứng im mãi mãi không nhận được Body.

---

### Bước 3: Bắt mạch trên Wireshark

1. Bắt gói tin **trong container** rồi mở bằng Wireshark (chạy được trên cả macOS/Windows — xem mục [🦈 Bắt gói tin bằng Wireshark](../README.md#-bắt-gói-tin-bằng-wireshark-trên-mọi-hệ-điều-hành) ở README series).
2. Display filter:
   ```wireshark
   tcp.port == 80 || icmp
   ```
3. Soi gói tin:
   * Thấy quá trình bắt tay TCP `[SYN]` -> `[SYN, ACK]` -> `[ACK]` thành công.
   * Thấy gói tin Client gửi request `GET /` thành công.
   * Sau đó xuất hiện hàng loạt gói tin Server gửi lại dữ liệu lớn **`[TCP Retransmission] Len=1460`** vì Server không nhận được ACK từ Client!

---

### Bước 4: Khắc Phục Sự Cố (Fix & Remediate)

```bash
./scripts/2-fix.sh
```

> **Cách chữa của lab (MSS Clamping thật):** script **KHÔNG gỡ luật chặn gói lớn** — mô phỏng tình huống thực tế bạn không sửa được đường truyền nghẽn (VPN/tunnel/cloud của bên thứ ba). Thay vào đó nó kẹp MTU của route tới client xuống `940`:
> ```bash
> ip route replace 172.28.4.20/32 dev eth0 mtu 940
> ```
> Server tự tính MSS gửi đi `= 940 − 40 = 900 bytes`, nên mọi segment server→client tối đa ~940 bytes, **luôn nhỏ hơn ngưỡng 1000 bytes bị DROP** → Web tải trọn vẹn dù "đường ống" vẫn nghẽn.

Kiểm tra lại:
```bash
./scripts/test.sh
```
Trước khi chữa: `tải về 0 bytes` (curl treo 8s). Sau khi chữa: `tải về 3093 bytes | 0.6s`.

---

## 🧠 Bác Sĩ Mạng Đúc Kết: Giải Pháp Thực Tế Cho Lỗi MTU

1. **Nguyên nhân thực tế:** Thường xuyên xảy ra khi dữ liệu đi qua **VPN IPsec, GRE Tunnel, VXLAN, PPPoE** (các giao thức này đóng thêm Header làm giảm MTU khả dụng từ 1500 xuống 1400-1420).
2. **Đơn thuốc xử lý (Best Practices):**
   * **TCP MSS Clamping (Khuyên dùng nhất trên Router/Firewall):**
     `iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu`
     👉 Router tự động sửa giá trị MSS trong gói SYN thành kích thước nhỏ an toàn.
   * **Không bao giờ chặn ICMP Type 3 Code 4:** Mở Firewall cho phép gói ICMP thông báo "Fragmentation Needed".

---

## 📝 Câu Hỏi Ôn Tập

1. Vì sao `ping` gói nhỏ chạy tốt, bắt tay TCP thành công, nhưng tải trang web lại đơ giữa chừng?
2. TCP MSS Clamping khắc phục lỗi này bằng cơ chế nào (mà không cần sửa "đường ống" nghẽn)?
3. Vì sao **tuyệt đối không** được chặn gói ICMP Type 3 Code 4?

<details><summary>Gợi ý đáp án</summary>

1. Gói nhỏ (ping, SYN) lọt qua; nhưng segment dữ liệu lớn vượt MTU đường truyền bị DROP âm thầm → nghẽn khi truyền data lớn (PMTUD Blackhole).
2. Kẹp MSS/MTU của route để host chỉ gửi segment nhỏ hơn ngưỡng nghẽn — data không bao giờ chạm mức bị drop (lab đặt route MTU 940 → MSS 900).
3. ICMP Type 3 Code 4 ("Fragmentation Needed") là cách mạng báo "gói quá to, hãy giảm kích thước". Chặn nó = tắt cơ chế PMTUD → sinh ra blackhole.
</details>

---

## 🧹 Dọn dẹp Lab
```bash
docker compose down
```
