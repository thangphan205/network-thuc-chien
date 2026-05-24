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

# Tập 2 - Pod Network
## Giải phẫu Pause Container, veth pair & Network Namespace

**Phần 0 — Nền tảng K8s Networking** · `#pause` `#veth` `#namespace` `#linux`
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## 🗺 Lộ trình bài học: Lab First - Slide Second

Hôm nay chúng ta sẽ tiếp tục bóc tách "thế giới ngầm" của Pod bằng cách làm trước, lý giải sau:

*   **PHẦN 1: Thực hành điều tra (Lab First)**
    - Lẻn vào Network Namespace của Pod từ OS vật lý bằng `nsenter`.
    - Lùng sục "sợi dây cáp ảo" `veth` và switch ảo `cni0`.
    - Giả lập crash ứng dụng để xem mạng K8s bền vững thế nào.
    
*   **PHẦN 2: Giải phẫu kiến trúc (Slide Second)**
    - Sơ đồ hóa Pod thực chất là gì dưới góc nhìn Linux Kernel.
    - Giải nghĩa vai trò của "kẻ canh giữ mạng" — Pause Container.
    - Làm rõ nguyên lý sợi dây cáp ảo `veth pair`.

---

<!-- _class: lab -->

## 🔬 PHẦN 1: Bắt đầu làm Lab ngay!

Chúng ta sẽ thực hiện các Thí nghiệm đột phá trong file `lab-guide.md`:

1.  **Thí nghiệm 1 & 2:** Tìm PID của pause container và dùng `nsenter -t <PID> -n ip addr` để nhìn trộm card mạng của Pod từ máy Host.
2.  **Thí nghiệm 3:** Truy tìm sợi cáp mạng ảo `veth` và xem cách nó cắm vào bridge `cni0`.
3.  **Thí nghiệm 4:** Dùng `crictl stop` để kill chết container ứng dụng, chứng kiến container hồi sinh nhưng IP mạng vẫn giữ nguyên tuyệt đối.

👉 **Hãy tạm dừng video, mở terminal và bắt đầu gõ lệnh trong tệp `lab-guide.md` nhé!**

---

## 🔬 PHẦN 2: Đúc kết từ Lab — Hiện tượng kỳ bí

Sau bài Lab vừa rồi, chúng ta gặp 2 hiện tượng cực kỳ thú vị:

1.  **Hiện tượng 1**: Địa chỉ IP mạng của Pod thực chất lại hiển thị dưới PID của một tiến trình có tên là `/pause` chứ không phải PID của container ứng dụng (Nginx/Netshoot).
2.  **Hiện tượng 2**: Khi chúng ta cố tình "hạ sát" container ứng dụng bằng lệnh `crictl stop`, Kubernetes tự khởi động lại container mới, cột RESTARTS tăng lên 1, nhưng địa chỉ IP của Pod hoàn toàn **không bị thay đổi**!

👉 *Tại sao lại như vậy? Chúng ta hãy cùng bóc tách lý thuyết.*

---

## Sơ đồ "Thế giới ngầm" của một Pod

Hầu hết các tài liệu cơ bản nói: *"Pod là container"*. Điều này **chưa chính xác**.
Thực chất, **Pod = Nhóm các container chia sẻ cùng một Network Namespace**:

```
┌────────────────────────────────────────────────────────────────┐
│                           POD                                  │
│  ┌─────────────────────────┐      ┌─────────────────────────┐  │
│  │   PAUSE CONTAINER       │      │   APP CONTAINER         │  │
│  │   (Infra Container)     │      │   (Nginx / Netshoot)    │  │
│  │                         │      │                         │  │
│  │  - Giữ Namespace sống   │      │  - Join vào Namespace   │  │
│  │  - Làm mỏ neo mạng      │      │    của Pause Container  │  │
│  └─────────────────────────┘      └─────────────────────────┘  │
│                                                                │
│            Network Namespace (eth0: 10.244.1.5, lo)            │
└────────────────────────────────────────────────────────────────┘
```
- **Pause container** được sinh ra đầu tiên để tạo ra Network Namespace và "neo" nó lại.
- Nếu App container bị crash và biến mất, Network Namespace vẫn tồn tại nhờ Pause container vẫn sống. Khi App container khởi động lại, nó chỉ cần join lại namespace đó → **IP Pod được giữ vững!**

---

## veth pair: Sợi cáp ảo kết nối Pod ra ngoài Host

Làm thế nào gói tin đi ra khỏi Network Namespace bị cô lập của Pod để lên OS vật lý?
CNI sử dụng cơ chế **`veth pair` (Virtual Ethernet Pair)** giống như một sợi dây cáp ảo:

```
    Pod Namespace (Cô lập)       │      Root Namespace (OS vật lý)
  ┌────────────────────────┐     │     ┌──────────────────────────┐
  │         eth0           │     │     │      veth8a3f2b (No IP)  │
  │      10.244.1.5        │◄────┼────►│            │             │
  │         /24            │     │     │      cni0 bridge         │
  └────────────────────────┘     │     │      10.244.1.1/24       │
                                 │     └──────────────────────────┘
```
*   `veth pair` luôn được tạo thành cặp: 1 đầu cắm vào Pod (đặt tên là `eth0`), 1 đầu nằm ngoài host (đặt tên ngẫu nhiên như `vethXXXX`).
*   Mọi gói tin chui vào đầu `eth0` trong Pod sẽ tự động chột ra đầu `vethXXXX` ngoài host, và được chuyển tiếp trực tiếp vào switch ảo `cni0`.

---

## Key Takeaways — Bài học cốt lõi

*   **Pause container là anh hùng thầm lặng**: Nhẹ (~300KB), không làm gì ngoài việc ngủ (`sleep infinity`), nhưng chịu trách nhiệm giữ sinh mệnh mạng cho Pod.
*   **veth pair và bridge**: Cấu trúc mạng K8s cục bộ hoạt động y hệt cách bạn cắm dây mạng LAN từ máy tính vào một Switch vật lý trong nhà.
*   **`nsenter` là vũ khí debug tối thượng**: Giúp kỹ sư hệ thống bỏ qua lớp bảo mật K8s để trực tiếp nhảy vào Linux Kernel kiểm tra cấu hình mạng.

> **Tập tiếp theo:** IP của Pod rất dễ thay đổi khi Pod bị xóa hẳn. Làm thế nào để tạo một địa chỉ IP ảo cố định? Cùng tìm hiểu Service & kube-proxy!
