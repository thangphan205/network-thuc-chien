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

# Tập 4 - Thuế "ndots:5" và Tối ưu DNS
## Vạch trần lãng phí băng thông & 3 kỹ thuật trốn thuế DNS K8s

**Phần 0 — Nền tảng K8s Networking** · `#DNS` `#CoreDNS` `#ndots` `#Headless`
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## 🗺 Lộ trình bài học: Lab First - Slide Second

Hôm nay chúng ta sẽ phơi bày một "sự lãng phí ngầm" trong mạng K8s và cách khắc phục:

*   **PHẦN 1: Thực hành bắt quả tang (Lab First)**
    - Dùng `tcpdump` nghe lén lưu lượng DNS bên trong Pod.
    - Đếm số lượng queries thừa khi gọi API bên ngoài (Internet).
    - Thử nghiệm 3 cách cấu hình để triệt tiêu queries rác.
    - So sánh dịch DNS của Service thường với Headless Service.
    
*   **PHẦN 2: Giải phẫu cơ chế (Slide Second)**
    - Phân tích file cấu hình `/etc/resolv.conf` của Pod.
    - Giải thích cặn kẽ thông số `ndots:5` và cơ chế search paths.
    - Đúc kết cẩm nang tối ưu mạng DNS cho môi trường Production.

---

<!-- _class: lab -->

## 🔬 PHẦN 1: Bắt đầu làm Lab ngay!

Chúng ta sẽ thực hiện các Thí nghiệm đột phá trong file `lab-guide.md`:

1.  **Thí nghiệm 1:** Chạy `tcpdump` nghe lén UDP port 53 trên `pod-a`. Chạy curl tới `httpbin.org`. Chứng kiến cảnh 1 lần curl gửi ra tận **4 queries DNS** rác!
2.  **Thí nghiệm 2:** Thử nghiệm trốn thuế siêu tốc bằng cách thêm dấu chấm cuối tên miền: `curl httpbin.org.` và chứng kiến số lượng query giảm về **1**.
3.  **Thí nghiệm 3:** Ép cấu hình `ndots:2` bằng cách khai báo `dnsConfig` trong YAML của Pod.
4.  **Thí nghiệm 4:** Tạo Headless Service (`clusterIP: None`) và chạy `nslookup` để thấy DNS trả về trực tiếp danh sách IP thật của Pod.

👉 **Hãy tạm dừng video, mở terminal và bắt đầu gõ lệnh trong tệp `lab-guide.md` nhé!**

---

## 🔬 PHẦN 2: Tại sao 1 lệnh curl lại gửi đi 4 truy vấn DNS?

Hãy xem ruột file `/etc/resolv.conf` bên trong Pod của bạn:
```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

*   Khi bạn gọi `httpbin.org` (tên miền chỉ có **1 dấu chấm**), vì số lượng dấu chấm nhỏ hơn quy định (`ndots:5`), Linux cho rằng đây là một tên miền viết tắt nội bộ.
*   Nó sẽ tuần tự nối thêm các đuôi trong danh mục `search` để đi hỏi CoreDNS:
    1.  `httpbin.org.default.svc.cluster.local` (CoreDNS trả về NXDomain - Lỗi)
    2.  `httpbin.org.svc.cluster.local` (Lỗi)
    3.  `httpbin.org.cluster.local` (Lỗi)
    4.  `httpbin.org.` (Chọc ra DNS ngoài - Thành công!)
*   👉 **Hậu quả**: CoreDNS bị quá tải, ứng dụng bị trễ thời gian phân giải DNS khi gọi API bên ngoài!

---

## 3 Cách "Trốn Thuế" DNS trong Kubernetes

### Cách 1: Sử dụng FQDN (Dấu chấm thần thánh ở cuối)
Gọi tên miền có dấu chấm cuối: `httpbin.org.`
Dấu chấm này báo với hệ điều hành: *"Đây là tên miền tuyệt đối (Fully Qualified Domain Name). Trông tôi có vẻ ngắn nhưng tôi đã hoàn chỉnh rồi, đừng nối đuôi linh tinh nữa!"*. Linux sẽ bỏ qua toàn bộ search paths và chọc thẳng ra Internet.

### Cách 2: Cấu hình giảm `ndots` qua `dnsConfig`
Cài đặt `ndots:2` cho Pod. Bất kỳ tên miền nào có từ 2 dấu chấm trở lên (ví dụ: `api.github.com`) sẽ lập tức được giải quyết trực tiếp mà không cần đi qua danh sách tìm kiếm nội bộ.

### Cách 3: Headless Service cho Database/StatefulSet
Khi gọi các dịch vụ nội bộ có nhiều bản sao, sử dụng Headless Service (`clusterIP: None`). CoreDNS trả về trực tiếp danh sách IP Pod, bỏ qua kube-proxy giúp giảm tải thời gian định tuyến mạng.

---

## Key Takeaways — Bài học cốt lõi

*   **Sử dụng linh hoạt**:
    - Khi gọi dịch vụ **nội bộ**: Hãy dùng tên ngắn (ví dụ: `db`). Quy tắc `ndots:5` sẽ phát huy sức mạnh giúp tự điền đuôi `db.default.svc.cluster.local`.
    - Khi gọi dịch vụ **bên ngoài**: Bắt buộc phải thêm **dấu chấm ở cuối**, hoặc phải cấu hình giảm `ndots` trên file YAML của Deployment!
*   **Hiệu năng Production**: Trốn thuế DNS thành công có thể giúp cụm K8s lớn giảm từ 50% - 80% tải truy cập vào CoreDNS, ngăn chặn thảm họa nghẽn mạng do sập phân giải tên miền.

> **Tập tiếp theo:** Kubelet gọi CNI để cắm mạng như thế nào? CNI thực chất là gì? Hãy tự tay đóng vai Kubelet cắm mạng thủ công bằng cnitool!
