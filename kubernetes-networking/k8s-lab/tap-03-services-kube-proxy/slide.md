---
marp: true
theme: default
paginate: true
style: |
  section { font-family: 'Segoe UI', sans-serif; font-size: 22px; background: #0d1021; color: #e2e8f0; }
  h1 { color: #a78bfa; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #34d399; font-size: 1.4em; border-bottom: 2px solid #34d399; padding-bottom: 0.2em; }
  h3 { color: #fbbf24; font-size: 1.1em; }
  code { background: #1a1a35; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1a1a35; border-left: 4px solid #a78bfa; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
  th { background: #2d1b69; color: #e9d5ff; padding: 10px 14px; font-weight: 600; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a2050; color: #e2e8f0; background: #151530; }
  tr:nth-child(even) td { background: #1e1e40; }
  blockquote { border-left: 4px solid #fbbf24; padding-left: 16px; color: #cbd5e1; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  pre .hljs-comment, pre .hljs-meta { color: #7dd3fc; }
  pre .hljs-keyword, pre .hljs-selector-tag { color: #f9a8d4; }
  pre .hljs-string, pre .hljs-attr { color: #86efac; }
  pre .hljs-number, pre .hljs-literal { color: #fde68a; }
  pre .hljs-variable, pre .hljs-template-variable { color: #c4b5fd; }
  pre .hljs-built_in, pre .hljs-name { color: #67e8f9; }
  pre .hljs-subst { color: #e2e8f0; }
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

<br />
<br />

# Tập 3 - Services & kube-proxy
## Sự thật về ảo ảnh ClusterIP & Mổ xẻ bảng iptables

**Phần 0 — Nền tảng K8s Networking** · `#Service` `#ClusterIP` `#kube-proxy` `#iptables`
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## 🗺 Lộ trình bài học: Lab First - Slide Second

Hôm nay chúng ta sẽ giải mã một trong những ảo ảnh lớn nhất của Kubernetes:

*   **PHẦN 1: Thực hành đột nhập (Lab First)**
    - Chứng kiến cú lừa kinh điển: IP ảo `ping` thì chết nhưng `curl` lại chạy.
    - Chui xuống mức OS để lùng sục dấu vết `iptables` và đo tỷ lệ load balance ngẫu nhiên.
    - Soi "nhật ký dịch chuyển" bằng `conntrack`.
    
*   **PHẦN 2: Đúc kết bản chất (Slide Second)**
    - Phanh phui bản chất: ClusterIP có card mạng và địa chỉ MAC hay không?
    - Sơ đồ hóa chuỗi điệp vụ `iptables` do `kube-proxy` lập trình.
    - Cách NodePort mở cổng trên toàn cụm để dẫn đường cho traffic.

---

<!-- _class: lab -->

## 🔬 PHẦN 1: Bắt đầu làm Lab ngay!

Chúng ta sẽ thực hiện các Thực nghiệm cân não trong file `lab-guide.md`:

1.  **Thực nghiệm 1:** Tạo Service ClusterIP cho Nginx. Chứng minh cú sốc `ping ClusterIP` bị timeout nhưng `curl` lại trả về HTML vèo vèo.
2.  **Thực nghiệm 2:** Lên `worker1`, gõ grep iptables để lần theo các chuỗi `KUBE-SERVICES` -> `KUBE-SVC-xxx` -> `KUBE-SEP-xxx` để thấy xác suất rẽ nhánh thống kê.
3.  **Thực nghiệm 3:** Kiểm tra cache của module NAT thông qua lệnh `conntrack`.
4.  **Thực nghiệm 4:** Chuyển sang NodePort và dùng IP của bất kỳ Node nào để truy cập ứng dụng.

👉 **Hãy tạm dừng video, mở terminal và thực hiện lab theo tệp `lab-guide.md` nhé!**

---

## 🔬 PHẦN 2: Giải mã hiện tượng Ping Timeout vs Curl Success

Tại sao ClusterIP lại có hành vi kỳ lạ như vậy?

*   👉 **Câu trả lời**: **ClusterIP hoàn toàn không có thực!** Nó không được gán vào bất kỳ card mạng (NIC) vật lý hay ảo nào cả, và cũng không có địa chỉ MAC. Nó chỉ là một **ảo ảnh**!
*   Khi bạn `ping <ClusterIP>` (giao thức ICMP), gói tin gửi ra card mạng sẽ không có ai phản hồi vì IP đó không tồn tại trên thực tế -> Dẫn đến Timeout.
*   Khi bạn `curl <ClusterIP>:80` (giao thức TCP), `iptables` trên chính Node đó lập tức bắt gói tin (match rule), bẻ lái địa chỉ đích (DNAT) thành IP thật của Pod trước khi gói tin kịp rời khỏi Node!

---

## Sơ đồ luồng đi của gói tin qua Iptables

Khi bạn tạo một Service, `kube-proxy` sẽ chạy ngầm và cấu hình bảng `iptables -t nat` trên **MỌI NODE** theo sơ đồ chuỗi sau:

```
                  Gói tin TCP gửi đến ClusterIP:80
                                 │
                        [ KUBE-SERVICES ]
            (Bắt trúng IP của Service và cổng đích)
                                 │
                          [ KUBE-SVC-xxx ]
       (Sử dụng statistic mode random để chọn ngẫu nhiên Pod)
          ├── 33% Probability  ──► [ KUBE-SEP-pod1 ]
          ├── 50% Probability  ──► [ KUBE-SEP-pod2 ]
          └── 100% Probability ──► [ KUBE-SEP-pod3 ]
                                 │
                       (Thực hiện luật DNAT)
                                 ▼
                     Destination = IP thật của Pod
```

---

## Conntrack & NodePort: Cách K8s dẫn đường

### 1. Conntrack (Connection Tracking)
Khi iptables thực hiện DNAT (đổi IP ảo -> IP thật), nó cần ghi nhớ "nhật ký" ở module `conntrack` của Linux Kernel. Khi Pod phản hồi ngược lại, `conntrack` tự động dịch ngược (SNAT) thành IP ảo để Client không nhận ra sự thay đổi.

### 2. NodePort: Mở cổng trên toàn cụm
Khi đổi Service sang NodePort (ví dụ: `31234`), `kube-proxy` sẽ binding port đó trên **tất cả các card mạng của tất cả các node**. Iptables sẽ bắt traffic đập vào port này trên bất kỳ node nào và tự động chuyển hướng nó về đúng node chứa Pod.

---

## Key Takeaways — Bài học cốt lõi

*   **ClusterIP là ảo ảnh**: Toàn bộ cơ chế Service thực chất là một hệ thống phân phối luật **NAT (Network Address Translation)** khổng lồ do `kube-proxy` lập trình tự động trên nền tảng `iptables` của Linux Kernel.
*   **Load Balancing cấp hạt nhân**: K8s sử dụng tính năng xác suất thống kê có sẵn của Linux (`statistic mode random`) để chia tải, rất nhẹ và hiệu năng cao.
*   **Hạn chế của iptables**: Khi cụm có hàng ngàn Service, số lượng dòng iptables tăng lên tới hàng chục vạn dòng. Linux phải duyệt tuần tự $O(N)$ dẫn đến giảm hiệu năng -> Đây là lý do IPVS và eBPF ra đời!

> **Tập tiếp theo:** Làm thế nào để các Pod gọi nhau qua Tên thay vì IP ảo? Khám phá CoreDNS và sắc thuế DNS "ndots:5" cực kỳ lãng phí!
