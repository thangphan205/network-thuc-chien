# 💡 Cơm Thêm: Vì Sao Qua Proxy Triệu Chứng Lỗi Lại Bị Bóp Méo?

> Tài liệu bổ trợ chuyên sâu cho **Tập 03: Bind Localhost**.

---

## 1. Phân biệt bản chất 2 mã lỗi ở tầng TCP

| Tiêu chí | `Connection Refused` (`curl: (7)`) | `Connection Reset by Peer` (`curl: (56)`) |
| :--- | :--- | :--- |
| **Thời điểm xảy ra** | **Trong lúc bắt tay (Handshake phase)**. | **Sau khi đã bắt tay thành công (ESTABLISHED phase)**. |
| **Trạng thái kết nối** | Chưa từng được thiết lập. | Đã kết nối xong, đang chờ hoặc đang truyền dữ liệu thì bị ngắt đột ngột. |
| **Gói tin TCP** | Gửi `SYN` $\rightarrow$ Nhận ngay `RST, ACK`. | Đã xong `SYN -> SYN/ACK -> ACK` $\rightarrow$ Đột ngột nhận `RST`. |

---

## 2. Chi tiết luồng xử lý: Tại sao qua `docker-proxy` lại đổi mã lỗi?

Khi bạn expose port `8083:80`, Docker chạy một tiến trình `docker-proxy` (L4 TCP proxy) đứng nghe ở port `8083` trên máy Host.

Hãy so sánh 2 kịch bản:

### 🔹 Kịch bản 1: Gọi trực tiếp từ Client vào Container (Đúng L3 — Không qua proxy)
```
Client (172.28.3.20)                     Web Server (172.28.3.10)
      │                                             │
      │ ──── 1. TCP SYN (Port 80) ────────────────> │
      │                                             │ (Kernel thấy không có ai nghe)
      │ <─── 2. TCP RST, ACK ────────────────────── │
      ▼                                             
curl: (7) Failed to connect: Connection refused
```
*Kết nối bị từ chối ngay từ "cửa sổ bắt tay" $\rightarrow$ Báo lỗi `Connection refused`.*

---

### 🔹 Kịch bản 2: Gọi từ Host qua `docker-proxy` (Port 8083)
Tiến trình `docker-proxy` tách kết nối làm **2 phiên TCP độc lập**:

```
Host (curl)                                docker-proxy (Port 8083)                      Container (172.28.3.10:80)
    │                                                  │                                             │
    │ ─── 1. SYN ────────────────────────────────────> │                                             │
    │ <── 2. SYN, ACK (docker-proxy đang sống nên OK) ─│                                             │
    │ ─── 3. ACK ────────────────────────────────────> │                                             │
    │                                                  │                                             │
    │   [🎉 KẾT NỐI ĐÃ THÀNH CÔNG (ESTABLISHED)]       │                                             │
    │ ─── 4. HTTP GET / ─────────────────────────────> │                                             │
    │    (Host đang đợi phản hồi HTTP...)              │ ─── 5. SYN ───────────────────────────────> │
    │                                                  │ <── 6. RST, ACK (Bị từ chối ở đây!) ─────── │
    │                                                  │                                             │
    │                                                  │ (Chặng sau đứt, docker-proxy không thể)     │
    │                                                  │ (quay ngược thời gian từ chối SYN bước 1)   │
    │                                                  │                                             │
    │ <── 7. TCP RST (Hủy ngang kết nối đang mở) ───── │                                             │
    ▼                                                                                                
curl: (56) Recv failure: Connection reset by peer
```

👉 **Giải thích từng bước:**
1. Ở **Chặng 1** (Host $\leftrightarrow$ `docker-proxy`): Vì `docker-proxy` trên Host thực sự đang chạy và lắng nghe port `8083`, nó hoàn tất bắt tay 3 bước (`3-Way Handshake`) với `curl` hoàn toàn bình thường.
2. Ở **Chặng 2** (`docker-proxy` $\leftrightarrow$ Container): `docker-proxy` quay sang mở kết nối vào `172.28.3.10:80` thì bị Kernel của container ném trả `RST` (vì Nginx bên trong chỉ bind `127.0.0.1`).
3. Lúc này, kết nối ở Chặng 1 đã ở trạng thái **`ESTABLISHED`** và `curl` đang chờ dữ liệu. `docker-proxy` không thể làm gì khác ngoài việc **bắn gói `RST` để hủy bỏ phiên kết nối đang mở** $\rightarrow$ `curl` phát hiện phía bên kia đột ngột ngắt ngang nên báo lỗi **`(56) Connection reset by peer`**.

---

## 3. Bức tranh tổng thể: Các lớp Proxy bóp méo lỗi như thế nào?

Trong môi trường Production (Kubernetes, Microservices, Cloud), hiện tượng này xảy ra liên tục tùy thuộc vào tầng proxy bạn đang đi qua:

```
[Nguyên nhân gốc tại App]
App bind sai 127.0.0.1 / App crash / Port không lắng nghe
           │
           │ (Bản chất: Gói SYN nhận về RST)
           ▼
┌──────────────────────────────────────┬────────────────────────────────────────────────────────┐
│ Vị trí đứng test / Lớp trung gian    │ Triệu chứng bạn nhìn thấy                               │
├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
│ 1. Trực tiếp cùng mạng L3 (Pod-to-Pod)│ `curl: (7) Connection refused`                         │
│ 2. Qua L4 Proxy (docker-proxy, NLB)  │ `curl: (56) Connection reset by peer`                  │
│ 3. Qua L7 Proxy (Nginx, Envoy, ALB)  │ `HTTP 502 Bad Gateway`                                 │
│ 4. Qua CDN (Cloudflare)              │ `HTTP 521 Web Server Is Down` hoặc `502`               │
└──────────────────────────────────────┴────────────────────────────────────────────────────────┘
```

---

## 🎯 4. Bài học thực chiến cốt lõi

Khi nhận được các lỗi như `502 Bad Gateway`, `Connection reset by peer`, hay `Connection closed`:
1. **Đừng vội phán đoán lỗi nằm ở con Proxy/Ingress**: Phần lớn trường hợp, Proxy hoàn toàn vô tội — nó chỉ là người đưa tin bối rối khi backend phía sau từ chối kết nối.
2. **Quy tắc debug "bóc hành" (từ ngoài vào trong)**: 
   - Không debug qua domain/ingress/host port.
   - SSH/Exec thẳng vào mạng nội bộ (hoặc container lân cận) và `curl` trực tiếp vào **IP + Port gốc** của container/process đó để bắt được **triệu chứng L3 nguyên bản**.
