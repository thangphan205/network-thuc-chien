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

# Tập 1 - Kubernetes Network Model
## 4 nguyên tắc không NAT & Sức mạnh của CNI

**Phần 0 — Nền tảng K8s Networking** · `#NetworkModel` `#CNI` `#routing`
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## 🗺 Lộ trình bài học mới: Lab First - Slide Second

Chúng ta không bắt đầu bằng lý thuyết khô khan. Hôm nay, chúng ta sẽ đi theo mô hình lớp học đảo ngược:

*   **PHẦN 1: Thực hành thực tế (Lab First)**
    - Khởi động cụm K8s "trắng" để xem sự cố xảy ra khi thiếu card mạng.
    - Tự tay cài đặt mạng (CNI) và chứng kiến sự thay đổi của Linux.
    
*   **PHẦN 2: Đúc kết bản chất (Slide Second)**
    - Phân tích 4 nguyên tắc vàng của Kubernetes Network Model.
    - Khám phá cơ chế định tuyến (Routing) giải quyết bài toán không NAT.

---

<!-- _class: lab -->

## 🔬 PHẦN 1: Bắt đầu làm Lab ngay!

Chúng ta sẽ thực hiện 3 Thí nghiệm chuyên sâu trong file `lab-guide.md`:

1.  **Thí nghiệm 1:** Chứng kiến cảnh cụm K8s tê liệt khi chưa cài CNI (Node `NotReady`, Pod bị kẹt ở `Pending` mãi mãi).
2.  **Thí nghiệm 2:** Cài đặt Flannel CNI và xem các Node tự động "hồi sinh" chuyển sang `Ready`.
3.  **Thí nghiệm 3:** Lần mò "dấu vết" mạng mà CNI thiết lập trên hệ điều hành (`flannel.1` card, `cni0` bridge và bảng routing).

👉 **Hãy tạm dừng video, mở terminal và gõ lệnh theo hướng dẫn trong tệp `lab-guide.md` nhé!**

---

## 🔬 PHẦN 2: Đúc kết từ Lab — Hiện trạng bạn vừa thấy

Sau khi làm Lab, chúng ta phát hiện ra 2 trạng thái trái ngược hoàn toàn:

### 1. Trạng thái "Vô danh" (Chưa cài CNI)
- Lệnh `kubectl get nodes` báo `NotReady`. Kubelet báo lỗi: `network plugin is not ready`.
- Card mạng trên Node chỉ có các cổng cơ bản (`eth0`, `lo`). Hoàn toàn không có card mạng nào cho Pod.

### 2. Sau khi cài CNI (Flannel)
- Mọi node chuyển sang `Ready` thần tốc. Pod chuyển `Running` và có IP riêng.
- Card mạng ảo mới xuất hiện: `cni0` (bridge) và `flannel.1` (VTEP VXLAN).
- Bảng định tuyến (`ip route`) xuất hiện dòng: `10.244.x.x` đi qua các card mạng ảo này.

---

## 📜 Hợp đồng mạng: Kubernetes Network Model

Kubernetes **không tự cài mạng**, nó chỉ đặt ra một **hợp đồng bắt buộc** gồm 4 nguyên tắc vàng mà bất kỳ CNI nào cũng phải tuân thủ:

```
Nguyên tắc 1: Pod-to-Pod không NAT (dù khác Node)
──────────────────────────────────────────────────
Pod A IP: 10.244.1.5  →  Pod B IP: 10.244.2.7 (Giữ nguyên IP nguồn)

Nguyên tắc 2: Node-to-Pod không NAT
──────────────────────────────────────────────────
Worker node IP: 192.168.64.11  →  Pod IP: 10.244.2.7 (Đến thẳng trực tiếp)

Nguyên tắc 3: Pod thấy đúng IP nguồn của caller
──────────────────────────────────────────────────
Pod B nhận gói tin: src_ip = 10.244.1.5 (Không bị NAT thành IP của Node)

Nguyên tắc 4: Pod IP là độc bản trên toàn bộ Cluster
──────────────────────────────────────────────────
Không bao giờ có 2 Pod trùng IP nhau, dù chúng nằm ở bất kỳ đâu
```

---

## Tại sao quy tắc "Không NAT" lại khó?

*   **Mạng thông thường (Có NAT):**
    Router chỉ cần định tuyến cho IP của máy Host (`192.168.x.x`). Traffic đi ra ngoài sẽ bị đổi IP nguồn (Masquerade) thành IP Host. Cực kỳ đơn giản cho thiết bị mạng vật lý.
    
*   **Mạng Kubernetes (Không NAT):**
    Gói tin đi từ Pod A sang Pod B bắt buộc phải giữ nguyên địa chỉ `10.244.1.5` làm IP nguồn.
    
*   👉 **Giải pháp**: Router vật lý phải biết đường đi của các dải mạng con `10.244.x.x`. CNI giải quyết việc này bằng 2 cách:
    1.  **Direct Routing** (Ví dụ Calico, Flannel host-gw): Quảng bá bảng định tuyến.
    2.  **Encapsulation/Overlay** (Ví dụ Flannel VXLAN): Bọc gói tin của Pod vào trong gói tin của Node (giống như gửi một bức thư bên trong một hộp bưu phẩm khác).

---

## Key Takeaways — Bài học cốt lõi

*   **CNI không phải là phép thuật**: Nó thực chất chỉ là một tiến trình tự động thực hiện các câu lệnh Linux cơ bản: Tạo card mạng ảo (`cni0`, `flannel.1`) và cấu hình bảng định tuyến (`ip route`).
*   **Mạng K8s là mạng phẳng (Flat Network)**: Mọi Pod có thể giao tiếp trực tiếp với nhau qua IP của nó mà không cần thông qua NAT.
*   **IP của Pod là duy nhất**: CNI chịu trách nhiệm phân chia các dải mạng con (Subnet) cho mỗi Node để không bao giờ xảy ra conflict IP.

> **Tập tiếp theo:** Ai đã cắm dây cáp ảo nối Pod ra ngoài thế giới? Pause container đóng vai trò gì? Hãy cùng khám phá `veth pair`!
