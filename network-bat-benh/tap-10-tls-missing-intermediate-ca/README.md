# 🩺 Ca Bệnh 10: Thiếu Intermediate CA — Chuỗi Tin Cậy Đứt Ở Đâu?

> **Hồ sơ ca bệnh:**
> * **Hiện tượng:** Kỹ sư mở Chrome trên máy tính truy cập website HTTPS thì thấy ổ khoá xanh bình thường. Nhưng người dùng mở bằng điện thoại, ứng dụng Mobile App, hoặc gọi API bằng `curl` / `Python requests` thì đứt gánh: **`unable to get local issuer certificate`**.
> * **Bản chất lỗi:** **Incomplete Certificate Chain ở Tầng 5/6 (TLS)**. Web server chỉ gửi Server Certificate (leaf) mà quên gửi kèm Intermediate CA để nối liền chuỗi tin cậy về Root CA.
> * **Nhưng đó mới là một nửa.** Cùng thông báo lỗi đó còn có một thủ phạm thứ hai, trái ngược hoàn toàn — và tập này tồn tại để tách hai cái đó ra.

> 🎯 **Buổi học chỉ cần 2 ca chính** (cùng dòng lỗi, hai thủ phạm trái ngược): **KB2** server gửi thiếu intermediate · **KB3** client thiếu root, cộng KB1 làm mốc. Các ca còn lại (đảo thứ tự, thừa root, intermediate hết hạn, AIA, sai người ký, cross-sign, trust store của runtime, chưa reload) vẫn chạy được, nằm trong [`scripts/mo-rong/`](./scripts/mo-rong/) và mô tả ở [kich-ban.md](./kich-ban.md) — để học tiếp, không nằm trong luồng chính.

---

## 🎯 Thứ Đáng Học Nhất Tập Này

Client **không** xác thực một cert. Nó xác thực một **đường đi**:

```
   [leaf]  ──(1)──▶  [intermediate]  ──(2)──▶  [root trong trust store]

   Đoạn (1) do SERVER chịu trách nhiệm — server phải GỬI KÈM cert intermediate
   Đoạn (2) do CLIENT chịu trách nhiệm — máy phải CÓ SẴN root trong trust store
```

Đứt đoạn nào cũng in ra **đúng một dòng chữ**:

```
verify error:num=20:unable to get local issuer certificate
```

Thứ duy nhất tách được hai ca bệnh trái ngược này là con số **`depth`**:

| | `DEPTH=0` | `DEPTH=1` |
| :-- | :-- | :-- |
| Cert hỏng là | **leaf** | **intermediate** |
| Server gửi | 1 cert (thiếu) | 2 cert (đủ) |
| Thủ phạm | **SERVER** | **CLIENT** |
| Chữa | trỏ `ssl_certificate` → `fullchain` | cài root CA vào trust store |

> ⚠️ Vì vậy **không được chẩn đoán bằng `curl` một mình.** curl in dòng chữ, không in depth.
> Phải gõ `openssl s_client` và đọc dòng `depth=` ngay **trước** dòng `verify error`.

---

## 🔬 Sơ đồ Kiến trúc Lab

```
                              172.28.10.0/24
  ┌──────────────────┐   ┌──────────────────────┐   ┌────────────────────┐
  │  client   .20    │   │  web-server   .10    │   │  aia         .30   │
  │  ALPINE          │   │                      │   │                    │
  │  curl openssl    │──▶│  nginx 443           │   │  nginx 80          │
  │  node python java│   │  gửi 1 trong 8 CHUỖI │   │  intermediateCA.der│
  │  tcpdump         │   │                      │◀──│  (cho MR4)         │
  └──────────────────┘   └──────────────────────┘   └────────────────────┘
        │                         ▲
        │                         │
  ┌──────────────────┐            │
  │ client-node .21  │────────────┘
  │ DEBIAN + node    │   ← MR7: cùng CA, khác cách image đóng gói
  │ chính thức       │
  └──────────────────┘

        trust store: CÓ / KHÔNG có root CA của lab  ← KB3 sống ở đây

  Chuỗi chứng chỉ (sinh tự động mỗi lần `docker compose up`):

        [Lab10 Root CA]                    ← client giữ, trong trust store
              │ ký
              ▼
        [Lab10 Intermediate CA]            ← MẮT XÍCH HAY BỊ QUÊN
              │ ký
              ▼
        [app.chain.local]                  ← server gửi
```

> **Lưu ý:** Chứng chỉ được service `certgen` **sinh tự động** mỗi lần `docker compose up`,
> nên lab không bao giờ hỏng vì cert hết hạn dù bạn chạy vào năm nào. Cert "hết hạn" của MR3
> có `notAfter` cố định trong quá khứ nên nó hết hạn **vĩnh viễn**.

**Vì sao client là một container riêng, không dùng `curl` của máy thật?**
macOS ship LibreSSL, Linux ship OpenSSL. Hai bản in mã verify và số depth theo định dạng
**khác nhau** — mà số depth lại chính là thứ cả tập này dựa vào.

---

## 🚀 Hướng Dẫn Thực Hành

### Dựng lab

```bash
cd network-bat-benh/tap-10-tls-missing-intermediate-ca
./scripts/0-setup.sh
```

Script này dựng lab, cài root CA vào trust store của client, đặt chuỗi đầy đủ, rồi **khẳng
định** trạng thái khoẻ (`num=0`, HTTP 200) trước khi trả quyền cho bạn.

### Ba terminal

```bash
# Terminal 1 — chạy kịch bản
./scripts/2-thieu-intermediate.sh

# Terminal 2 — máy đo phía client (nạn nhân)
docker exec -it lab10-client monitor.sh

# Terminal 3 — góc nhìn phía server (chuỗi đang thực sự gửi ra dây)
./scripts/xem-chuoi.sh
```

Ca bệnh này chia trách nhiệm giữa hai đầu, nên **chỉ nhìn một phía thì không bao giờ tách
được** "server gửi thiếu" khỏi "client thiếu root".

### Chạy một ca bệnh và đọc chữ ký

```bash
./scripts/1-binh-thuong.sh              # mốc so sánh
./scripts/2-thieu-intermediate.sh       # ⭐ server gửi thiếu    → DEPTH=0
./scripts/3-thieu-root-o-client.sh      # ⭐ client thiếu root   → DEPTH=1   (ca khác: scripts/mo-rong/)
./scripts/0-setup.sh                    # reset sau mỗi ca
```

> 👉 **Chạy KB2 rồi KB3 liền nhau.** Toàn bộ bài học nằm ở chỗ chỉ một con số trên màn hình
> đổi từ `0` thành `1`, còn mọi dòng chữ khác thì giống hệt.

Chi tiết các kịch bản (kể cả ca mở rộng): **[kich-ban.md](./kich-ban.md)**.

### Bắt gói tin

```bash
./scripts/bat-goi-tls.sh 12
```

> ⚠️ **Wireshark KHÔNG cho bạn thấy "chuỗi tin cậy bị đứt".**
> Việc xác thực chuỗi xảy ra hoàn toàn **bên trong** client, sau khi gói tin đã đến nơi.
> Trên dây không hề có gói nào tên là "chain error". Wireshark trả lời được câu *"server gửi
> gì"* (đếm được số cert), và **không** trả lời được câu *"client nghĩ gì về cái đó"* — mà
> toàn bộ tập này xoay quanh câu thứ hai.
>
> Nhưng có đúng một thứ nó làm tốt hơn mọi công cụ khác: cho thấy bản tin `Certificate`
> **phình to ra** khi chuỗi dài thêm. Lọc: `tls.handshake.type == 11`.
>
> ⚠️ **Script mặc định ép TLS 1.2, và đó là cố ý.** nginx đàm phán TLS 1.3, mà TLS 1.3
> **mã hoá** bản tin Certificate — mở Wireshark lọc `tls.handshake.type == 11` sẽ ra
> **danh sách rỗng**. Tự kiểm chứng: `./scripts/bat-goi-tls.sh 12 13` rồi lọc lại.

---

## 🧠 Bảng Vân Tay — Thứ Đáng Học Thuộc Nhất Tập Này

| KB | Kịch bản | `#cert` | `num` | **`DEPTH`** | `curl` | Thủ phạm | Chữa |
| :-- | :--- | :--: | :--: | :--: | :--: | :--- | :--- |
| KB1 | chuỗi đầy đủ | 2 | `0` | — | 200 | — | — |
| KB2 | **server gửi thiếu** | **1** | `20` | **0** | 60 | **SERVER** | trỏ sang `fullchain` |
| KB3 | **client thiếu root** | 2 | `20` | **1** | 60 | **CLIENT** | cài CA vào trust store |
| MR1 | chuỗi đảo ngược | — | nginx **chết** | — | — | SERVER | ghép lại: leaf TRƯỚC |
| MR2 | thừa root | **3** | `0` | — | **200** | không hỏng | bỏ root (không gấp) |
| MR3 | intermediate hết hạn | 2 | `10` | **1** | 60 | intermediate | xin intermediate mới |
| MR4 | thiếu + có AIA | **1** | `20` | **0** | 60 | SERVER | trỏ sang `fullchain` |
| MR5 | **2 cert nhưng sai người ký** | **2** | `20` | **0** | 60 | SERVER | lấy đúng bundle của CA đã ký |
| MR6 | cross-sign, root cũ hết hạn | 3 | `0` **hoặc** `10` | **3** | tuỳ máy | TRUST STORE của máy | cập nhật CA bundle |
| MR7 | runtime có store riêng | 2 | `0` | — | 200 | **RUNTIME** | `NODE_EXTRA_CA_CERTS`… |
| MR8 | sửa file, chưa reload | 1 | `20` | **0** | 60 | quy trình | reload thật |

> ⚠️ **Đếm cert là gợi ý, KHÔNG phải bằng chứng.** MR5 gửi đủ 2 cert mà vẫn `20 @ depth 0`,
> vì cert gửi kèm là intermediate của một CA khác. Quy tắc đúng:
> **`issuer` của tầng N phải trùng `subject` của tầng N+1** — với mọi N.

**Mã verify của OpenSSL cần nhớ:**

| Mã | Nghĩa | Đọc thêm gì |
| :-- | :--- | :--- |
| `0` | ok | — |
| `10` | certificate has expired | **depth** — tầng 0 hay tầng 1? |
| `19` | self-signed certificate in certificate chain | root gửi kèm mà không được tin |
| `20` | unable to get local issuer certificate | **depth** — server thiếu hay client thiếu? |
| `21` | unable to verify the first certificate | chuỗi đứt ngay tầng dưới cùng |

`curl` exit **60** là mã chung cho mọi lỗi xác thực cert — nó **không** phân biệt được gì.

---

## 🧭 Quy Trình Debug Chuỗi Tin Cậy — 5 Bước, Đúng Thứ Tự

```bash
# 1. Server đang GỬI RA DÂY bao nhiêu cert? (không đọc file trên đĩa)
echo | openssl s_client -connect example.com:443 -servername example.com -showcerts 2>&1 \
  | grep -c 'BEGIN CERTIFICATE'
#    1 = gần như chắc chắn thiếu chuỗi.  2 = chuẩn.  3 = có kèm root (thừa, không sai).

# 2. Nó đứt ở DEPTH mấy?  ⭐ BƯỚC QUAN TRỌNG NHẤT
echo | openssl s_client -connect example.com:443 -servername example.com 2>&1 \
  | grep -E '^depth=|^verify error'
#    depth=0 + num=20  ->  SERVER gửi thiếu
#    depth=1 + num=20  ->  CLIENT thiếu root

# 3. Chuỗi có đúng thứ tự không? (tầng 0 phải là chính tên miền của bạn)
echo | openssl s_client -connect example.com:443 -servername example.com 2>&1 \
  | grep -E '^ *[0-9]+ s:|^ *i:'

# 4. Từng tầng còn hạn không? — đọc CẢ tầng 1, không chỉ tầng 0
echo | openssl s_client -connect example.com:443 -servername example.com -showcerts 2>&1 \
  | awk '/BEGIN CERT/,/END CERT/' | openssl x509 -noout -subject -dates

# 5. Trust store của MÁY NÀY có CA đó không?
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt leaf.pem
```

> 🧠 **Bước 2 trước bước 5.** Rất nhiều người nhảy thẳng xuống bước 5, thấy verify hỏng, rồi
> đi cài CA lung tung — trong khi lỗi nằm ở phía server và trust store hoàn toàn bình thường.

---

## 🌐 Xem Bằng Trình Duyệt — Phải Làm Đúng 2 Bước

```bash
# 1. Trỏ tên miền về máy mình (macOS/Linux)
echo "127.0.0.1 app.chain.local" | sudo tee -a /etc/hosts

# 2. Import root CA của lab vào trust store — nếu không, trình duyệt báo
#    ERR_CERT_AUTHORITY_INVALID và bạn đang xem nhầm sang KB3
#    macOS:
sudo security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain nginx/ssl/rootCA.crt
```

Rồi mở `https://app.chain.local:8444`.

> ⚠️ Vào thẳng `https://localhost:8444` sẽ ra lỗi **sai tên miền** — một ca bệnh hoàn toàn
> khác (tập 09 MR2), không liên quan gì đến chuỗi tin cậy.

**Đối chiếu kỳ vọng:**

| Kịch bản | Trình duyệt |
| :-- | :-- |
| KB2 (thiếu, không AIA) | `ERR_CERT_AUTHORITY_INVALID` — trừ khi trình duyệt đã cache intermediate |
| KB3 (client thiếu root) | `ERR_CERT_AUTHORITY_INVALID` — **cùng một màn hình đỏ**, khác thủ phạm |
| MR4 (thiếu, có AIA) | **vào bình thường** — trình duyệt tự tải intermediate về |

> Đúng cảnh mở đầu của tập: MR4 trên trình duyệt là ổ khoá xanh, còn `curl` thì chết.

---

## 📋 Bảng Script

| Script | Việc |
| :--- | :--- |
| `0-setup.sh` | Reset lab về trạng thái khoẻ. Chạy sau mỗi kịch bản. |
| `1-binh-thuong.sh`, `2-thieu-intermediate.sh`, `3-thieu-root-o-client.sh` | 3 kịch bản luồng chính |
| `mo-rong/3,4,5,7,8,9,10,11-….sh` | 8 ca mở rộng — xem [kich-ban.md](./kich-ban.md) |
| `xem-chuoi.sh` | Góc nhìn phía server, terminal 3 |
| `bat-goi-tls.sh [giây] [12\|13]` | Bắt gói ra `.pcap` + so kích thước bản tin Certificate |
| `test.sh` | Chạy cả 11 kịch bản (kể cả ca mở rộng), khẳng định 37 chữ ký. Dùng để kiểm tra lab còn đúng |
| `lib.sh` | Hằng số + hàm dùng chung |

---

## 📝 Câu Hỏi Ôn Tập

1. `curl` báo `unable to get local issuer certificate`. Bạn được gõ **đúng một lệnh** để
   biết thủ phạm là server hay client. Lệnh đó là gì, và bạn đọc con số nào?
2. Server gửi 2 cert, `num=20`. Có nên sửa cấu hình nginx không? Vì sao?
3. Đồng nghiệp bảo *"Chrome máy anh vào bình thường"*. Bạn hỏi lại câu gì?
4. `notAfter` của cert server là năm sau, mà curl vẫn báo `certificate has expired`.
   Chuyện gì đang xảy ra, và cấp lại cert server có chữa được không?
5. Vì sao chuỗi chuẩn **không** kèm root CA, dù kèm vào thì vẫn chạy?
6. Trong `/etc/letsencrypt/live/<domain>/` có `cert.pem` và `fullchain.pem`. Trỏ nginx vào
   cái nào, và cái còn lại gây ra ca bệnh nào?
7. nginx báo `key values mismatch` lúc khởi động. Chuỗi bị sai ở đâu?
8. Server gửi đủ 2 cert mà `openssl` vẫn báo `20 @ depth 0`. Chuyện gì xảy ra, và bạn kiểm
   tra bằng cách nào?
9. Cert của server còn hạn, không ai deploy gì, mà sáng nay 40% người dùng báo lỗi SSL —
   còn 60% vẫn bình thường. Nghi ngờ đầu tiên của bạn là gì?
10. `curl https://host/` trả 200 nhưng ứng dụng Node trên **cùng máy đó** báo
    `UNABLE_TO_GET_ISSUER_CERT_LOCALLY`. Sửa ở đâu — và vì sao **không** dùng
    `NODE_TLS_REJECT_UNAUTHORIZED=0`?

---

## 🧹 Dọn dẹp Lab

```bash
docker compose down -v
```
