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

# Tập 7
## Kiến trúc Flannel: flanneld, K8s API và CNI plugin hoạt động ra sao

**Phần 1 — Flannel** · `#flannel` `#flanneld` `#subnet` `#architecture`

---

## Mục tiêu tập này

- Giải thích vai trò của `flanneld`, K8s API, và CNI plugin trong Flannel
- Đọc subnet allocation từ K8s API (`podCIDR` và Node annotations)
- Trace luồng từ Node join cluster → Pod có IP
- Quan sát file `subnet.env` và bảng FDB mà flanneld tạo ra

**Prerequisites:** Cluster từ Tập 6 với Flannel VXLAN đang chạy

---

## 3 thành phần của Flannel

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
    flanneld (cp)  flanneld (w1)  flanneld (w2)
    DaemonSet      DaemonSet      DaemonSet
    ─────────      ─────────      ─────────
    • Đăng ký      • Đăng ký      • Đăng ký
      subnet         subnet         subnet
    • Cấu hình     • Cấu hình     • Cấu hình
      VTEP/routes    VTEP/routes    VTEP/routes
    • Ghi           • Ghi          • Ghi
      subnet.env     subnet.env     subnet.env
          │
          ▼
    CNI plugin (bridge binary)
    Đọc subnet.env → gán IP cho Pod
```

---

## Quy trình Node mới join cluster

```
1. worker2 join cluster
        ↓
2. flanneld khởi động trên worker2
        ↓
3. flanneld đọc podCIDR từ K8s API:
   kubectl get node worker2 -o jsonpath='{.spec.podCIDR}'
   → 10.244.2.0/24
        ↓
4. flanneld ghi annotation vào Node:
   flannel.alpha.coreos.com/public-ip = 192.168.64.12
        ↓
5. flanneld tạo VTEP interface (flannel.1) với IP 10.244.2.0
        ↓
6. flanneld ghi /run/flannel/subnet.env:
   FLANNEL_NETWORK=10.244.0.0/16
   FLANNEL_SUBNET=10.244.2.1/24
   FLANNEL_MTU=1450
   FLANNEL_IPMASQ=true
        ↓
7. flanneld trên các Node khác watch API → cập nhật FDB/ARP/routes
```

---

## FDB và ARP: "Bản đồ" định tuyến của VTEP

```
Trên worker1, khi gửi packet đến Pod B (10.244.2.7):

Route lookup:
  10.244.2.0/24 via 10.244.2.0 dev flannel.1
                         ↓
ARP table (flannel.1):
  10.244.2.0 → MAC cc:dd:ee:ff:11:22   (VTEP MAC của worker2)
                         ↓
FDB table (flannel.1):
  cc:dd:ee:ff:11:22 → dst 192.168.64.12  (IP vật lý của worker2)
                         ↓
Tạo VXLAN UDP packet → gửi đến 192.168.64.12:8472
```

**3 bảng, 3 câu trả lời:**
- Route: Subnet 10.244.2.x đi qua VTEP nào?
- ARP: VTEP gateway có MAC là gì?
- FDB: MAC đó thuộc Node IP nào?

---

<!-- _class: lab -->

## 🔬 Lab Time: Khám phá kiến trúc Flannel

Chúng ta sẽ thực hành:

1. **Xem subnet allocation:** Đọc podCIDR và Node annotation từ K8s API để thấy Flannel lưu trữ dữ liệu ở đâu.
2. **Đọc subnet.env:** Xem file giao tiếp giữa flanneld và CNI plugin — bridge biết IP range từ đây.
3. **Phân tích FDB và ARP:** Xem "bản đồ" 3 bước mà VTEP dùng để định vị Node đích.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

**Phân công trách nhiệm:**

| Component | Trách nhiệm |
| :--- | :--- |
| **K8s API** | Lưu `podCIDR` allocation, Node annotations |
| **flanneld** | Watch API, cấu hình VTEP/FDB/routes, ghi `subnet.env` |
| **CNI plugin** | Đọc `subnet.env`, gán IP cho Pod từ range đó |

**Files quan trọng:**
```
/run/flannel/subnet.env             ← flanneld → CNI plugin
/etc/cni/net.d/10-flannel.conflist  ← CNI config
/opt/cni/bin/flannel                ← CNI plugin binary
```

**Debug commands:**
```bash
bridge fdb show dev flannel.1       # VTEP MAC → Node IP
ip neigh show dev flannel.1         # Inner IP → VTEP MAC
kubectl get nodes -o custom-columns='NAME:.metadata.name,PODCIDR:.spec.podCIDR'
```

> **Tập tiếp theo:** VXLAN encapsulation — tcpdump soi packet thực tế, 50 bytes overhead đến từ đâu?
