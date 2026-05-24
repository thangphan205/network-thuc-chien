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

# Tập 5 - Giải phẫu CNI
## Đặc tả CNI Specification & Tự tay cắm mạng thủ công bằng cnitool

**Phần 0 — Nền tảng K8s Networking** · `#CNI` `#CNISpec` `#cnitool` `#linux-net`
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## 🗺 Lộ trình bài học: Lab First - Slide Second

Hôm nay chúng ta sẽ mở toang chiếc "hộp đen" mang tên CNI:

*   **PHẦN 1: Thực hành đóng vai (Lab First)**
    - Đột nhập `/opt/cni/bin` để truy tìm các file binary vô tri.
    - Soạn thảo hợp đồng mạng JSON `.conflist` chuẩn đặc tả.
    - Tạo Network Namespace Linux thủ công.
    - Đóng vai làm Kubelet dùng `cnitool` gọi CNI cắm/rút mạng (`ADD`/`DEL`).
    
*   **PHẦN 2: Giải phẫu đặc tả (Slide Second)**
    - Phân tích bản chất chuẩn đặc tả CNI Specification.
    - Giải nghĩa các biến môi trường và JSON đầu vào/đầu ra.
    - Kiến trúc tương tác giữa Kubelet và các CNI Plugins trong cụm.

---

<!-- _class: lab -->

## 🔬 PHẦN 1: Bắt đầu làm Lab ngay!

Chúng ta sẽ thực hiện các Thí nghiệm đột phá trong file `lab-guide.md`:

1.  **Thí nghiệm 1:** SSH vào `worker1`. Liệt kê các file binary CNI vô tri nằm trong `/opt/cni/bin/` (ví dụ: `bridge`, `host-local`, `loopback`).
2.  **Thí nghiệm 2:** Tự tay viết một hợp đồng cấu hình mạng JSON `mynet` có địa chỉ IPAM tĩnh `10.99.0.0/24`.
3.  **Thí nghiệm 3:** Khởi tạo Network Namespace `cni-test` và dùng `cnitool add` để ra lệnh cho CNI cắm mạng. Chứng minh namespace có card `eth0` và IP thành công!
4.  **Thí nghiệm 4:** Dùng `cnitool del` để thu hồi mạng sạch sẽ.

👉 **Hãy tạm dừng video, mở terminal và bắt đầu gõ lệnh trong tệp `lab-guide.md` nhé!**

---

## 🔬 PHẦN 2: Giải mã chiếc "hộp đen" CNI

Sau bài Lab, bạn đã phát hiện ra sự thật trần trụi về CNI:

*   👉 **CNI không phải là Daemon chạy ngầm!**
    Nó không lắng nghe trên bất kỳ port nào, cũng không chạy liên tục. Nó đơn giản chỉ là các file thực thi (binary) nằm im lìm trên đĩa cứng của Node.
*   👉 **CNI là một cái HỢP ĐỒNG (Specification)!**
    Hợp đồng này mô tả cách Container Runtime (như Kubelet) giao tiếp với CNI Plugins. Khi Pod được sinh ra, Kubelet chỉ cần **gọi trực tiếp** file binary đó, truyền dữ liệu JSON qua cổng vào tiêu chuẩn (`STDIN`) kèm một số biến môi trường, CNI Plugin làm xong việc và in trả lại kết quả cũng dưới dạng JSON!

---

## Giao diện Giao tiếp chuẩn Đặc tả CNI

Khi Kubelet gọi CNI Binary (ví dụ: gọi file `/opt/cni/bin/bridge`), nó truyền thông tin qua 2 kênh:

### 1. Biến môi trường bắt buộc (Environment Variables)
*   `CNI_COMMAND`: Hành động yêu cầu (`ADD`, `DEL`, `CHECK`, hoặc `VERSION`).
*   `CNI_CONTAINERID`: ID độc nhất của container.
*   `CNI_NETNS`: Đường dẫn tới Network Namespace (`/var/run/netns/...`).
*   `CNI_IFNAME`: Tên card mạng muốn đặt bên trong container (mặc định: `eth0`).
*   `CNI_PATH`: Đường dẫn tới thư mục chứa các CNI binary (ví dụ: `/opt/cni/bin`). Kubelet (và `cnitool`) dùng biến này để tìm file thực thi cần gọi.

### 2. Cấu hình mạng mô tả qua JSON (`STDIN`)
*   Truyền cấu hình dạng JSON (như file `.conflist` bạn vừa viết) mô tả loại card mạng (`bridge`), dải IP muốn cấp (`subnet`), gateway,... qua ngõ STDIN.

---

## Kiến trúc tương tác: Kubelet ↔ CNI Plugins

Trong một cụm K8s thực tế, quy trình cắm mạng diễn ra tự động y hệt như những gì bạn vừa làm thủ công bằng `cnitool`:

```
                       Pod mới được khởi tạo
                                 │
                         [ Kubelet ]
                                 │
             (1) Gọi binary /opt/cni/bin/bridge (ADD)
             (Truyền JSON qua STDIN + các biến CNI_*)
                                 │
                                 ▼
                       [ bridge CNI Plugin ]
            (Tạo veth-pair, chuyển 1 đầu vào Pod Namespace)
                                 │
                   (2) Ủy quyền cấp IP (Delegation)
                                 ▼
                     [ host-local IPAM Plugin ]
             (Lấy IP trống từ dải Subnet đã cấu hình)
                                 │
                                 ▼
      (3) Cắm mạng xong -> Trả kết quả JSON thành công cho Kubelet
```

---

## Key Takeaways — Bài học cốt lõi

*   **Đơn giản & Độc lập**: Đặc tả CNI được thiết kế cực kỳ tối giản. Bạn có thể sử dụng các CNI binaries này để tự xây dựng mạng cho các Linux container (Podman, containerd, hay netns thuần) mà không cần có Kubernetes.
*   **Vòng đời ngắn (Stateless)**: CNI plugins hoạt động theo kiểu "gọi xong rồi biến mất" (Stateless). Chúng chỉ khởi chạy, thực hiện cấu hình Linux (tạo card mạng, gán IP, route) trong vài mili-giây rồi tự chấm dứt tiến trình.
*   **Hành trình tiếp theo**: Bây giờ bạn đã hiểu gốc rễ cách cắm mạng. Trong các tập tiếp theo, chúng ta sẽ bắt đầu mổ xẻ sâu kiến trúc của ba ông lớn CNI trong thế giới Production: **Flannel → Calico → Cilium**!

> 🎉 **Chúc mừng bạn đã hoàn thành Phần 0 — Nền tảng K8s Networking!** Hãy sẵn sàng sang Phần 1 để khai phá CNI đầu tiên: Flannel!
