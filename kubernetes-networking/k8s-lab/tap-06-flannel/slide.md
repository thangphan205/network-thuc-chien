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

# Tập 6
## Cài đặt Flannel & Giải mã Kiến trúc Định tuyến L2/L3 (VXLAN Mode)

**Phần 1 — Flannel** · `#flannel` `#CNI` `#overlay` `#flanneld` `#FDB-ARP`

---

## Mục tiêu tập này

- Hiểu bài toán Pod-to-Pod cross-node communication và vai trò của CNI.
- Dựng cụm mạng Flannel từ con số 0 (từ cụm trắng NotReady).
- Khám phá kiến trúc 3 thành phần của Flannel: **K8s API**, **flanneld**, và **CNI plugin**.
- Phân tích chi tiết quy trình node join & giao tiếp 3 bước tĩnh của kernel: **Route $\rightarrow$ ARP $\rightarrow$ FDB**.

---

## Bài toán: 2 Pod, 2 Node, không nói chuyện được

```
Node 1 (192.168.64.11)         Node 2 (192.168.64.12)
┌───────────────────────┐      ┌───────────────────────┐
│ Pod A: 10.244.1.5/24  │      │ Pod B: 10.244.2.7/24  │
│ Default route:         │      │                       │
│  via 10.244.1.1 (cni0)│      │                       │
└───────────────────────┘      └───────────────────────┘

Pod A gửi packet đến 10.244.2.7:
  ip route show → không có route đến 10.244.2.0/24
  → packet bị DROP ngay tại Node 1 (no route to host)
```

**Giải pháp Flannel:** tạo virtual network phẳng (Overlay) qua VXLAN chui qua mạng vật lý.

---

## 3 thành phần cốt lõi của Flannel CNI

```
┌─────────────────────────────────────────────────┐
│              Kubernetes API / etcd              │
│   Node annotation: podCIDR + public-ip          │
│   controlplane: 10.244.0.0/24                   │
│   worker1:      10.244.1.0/24                   │
│   worker2:      10.244.2.0/24                   │
└──────────────────────┬──────────────────────────┘
                       │ watch
          ┌────────────┼────────────┐
          ▼            ▼            ▼
    flanneld (cp)  flanneld (w1)  flanneld (w2)  (DaemonSet)
    ───────────────────────────────────────────
    • Lắng nghe sự kiện Node Added/Modified từ K8s API.
    • Tạo VTEP interface (flannel.1), ghi /run/flannel/subnet.env.
    • Cấu hình các bảng tĩnh ARP/FDB/Route trên Node Host.
          │
          ▼
    CNI plugin (bridge binary)
    Đọc subnet.env → gán IP cho Pod khi Kubelet tạo Pod.
```

---

## Cơ cấu giao tiếp giữa flanneld và CNI plugin

- **flanneld** là "bộ não" quản lý Control Plane (watch API, setup routing table, static ARP, FDB).
- **CNI bridge plugin** là "tay chân" quản lý Data Plane ở local (tạo veth pair, gán IP Pod, cắm vào `cni0`).
- **subnet.env** là "hợp đồng" giao tiếp giữa bộ não và tay chân:

```ini
FLANNEL_NETWORK=10.244.0.0/16
FLANNEL_SUBNET=10.244.1.1/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
```

---

## FDB và ARP: "Bản đồ" định tuyến 3 bước của VTEP

Trên `worker1`, khi gửi packet đến Pod B (`10.244.2.7` trên `worker2`):

```
1. Route lookup:
   Đích 10.244.2.0/24 via 10.244.2.0 dev flannel.1 onlink (next hop là 10.244.2.0)
                         ↓
2. ARP table (flannel.1):
   10.244.2.0 → MAC cc:dd:ee:ff:11:22   (VTEP MAC của worker2)
                         ↓
3. FDB table (flannel.1):
   cc:dd:ee:ff:11:22 → dst 192.168.64.12  (IP vật lý của worker2)
                         ↓
Tạo VXLAN UDP packet (Dst Port: 8472) → gửi đến 192.168.64.12
```

- **Route:** Subnet IP Pod đích đi qua VTEP nào?
- **ARP:** VTEP gateway đối diện có MAC là gì?
- **FDB:** MAC VTEP đó tương ứng với IP vật lý nào của Node?

---

<!-- _class: lab -->

## 🔬 Lab Time: Dựng Flannel & Mổ xẻ cơ chế định tuyến

Chúng ta sẽ thực hành các bước sau trong file hướng dẫn `lab-guide.md`:

1. **Quan sát cụm trắng:** Xem xét trạng thái `NotReady` của node và sự thiếu hụt định tuyến.
2. **Cài đặt & Theo dõi:** Dựng Flannel CNI và quan sát card ảo `flannel.1`, bridge `cni0` xuất hiện.
3. **Trace Route, ARP, FDB:** Soi tận mắt 3 bảng dữ liệu mà Kernel Linux dùng để điều hướng packet.
4. **Giả lập sự cố:** Tự tay mô phỏng lỗi sai card mạng chính (`--iface`), lỗi lệch subnet của bridge `cni0` và lỗi tường lửa chặn VXLAN.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

**Phân công trách nhiệm:**
- **K8s API:** Lưu trữ `podCIDR` allocation và Node annotations (MAC VTEP, public-ip).
- **flanneld:** Watch API, setup `flannel.1` interface, điền các bảng ARP/FDB/Route, ghi `subnet.env`.
- **CNI plugin:** Đọc `subnet.env`, delegate xuống bridge plugin để cắm mạng và gán IP cho Pod.

**Bảng tra cứu tĩnh:**
Nhờ `flanneld` đồng bộ tĩnh các bảng ARP và FDB từ trước, Kernel có thể đóng gói VXLAN và gửi gói tin cross-node ngay lập tức mà không cần bất kỳ giao thức khám phá động (dynamic discovery) nào khi packet truyền qua.

> **Tập tiếp theo:** VXLAN Backend — tcpdump soi gói tin thực tế, 50 bytes overhead đến từ đâu?
