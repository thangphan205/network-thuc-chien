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

# Tập 6 - Flannel
## Cài đặt Flannel & Giải mã Kiến trúc Định tuyến L2/L3 (VXLAN Mode)

**Phần 1 — Flannel** · `#flannel` `#CNI` `#overlay` `#flanneld` `#FDB-ARP`

![height:200px](https://github.com/flannel-io/flannel/blob/master/logos/flannel-horizontal-color.png?raw=true)

---

## Mục tiêu tập này

- Hiểu **tại sao** Pod cross-node không nói chuyện được khi chưa có CNI.
- Dựng Flannel từ cụm trắng `NotReady` → quan sát từng thay đổi xảy ra.
- Nắm 3 tầng của Flannel: **K8s API → flanneld → CNI plugin**.
- Đọc tận mắt 3 bảng kernel điều hướng packet: **Route → ARP → FDB**.

---

## Vấn đề: Pod A không biết đường đến Pod B

```
Node 1 (192.168.64.11)          Node 2 (192.168.64.12)
┌──────────────────────┐        ┌──────────────────────┐
│  Pod A: 10.244.1.5   │        │  Pod B: 10.244.2.7   │
└──────────────────────┘        └──────────────────────┘

Pod A hỏi kernel: "Đường nào đến 10.244.2.0/24?"
→ ip route show: không có route
→ Kernel DROP packet ngay tại Node 1
```

> **Flannel giải quyết:** tạo VXLAN tunnel, bọc gói tin trong UDP rồi chuyển qua mạng vật lý.

---

## Flannel hoạt động qua 3 tầng

| Tầng | Vai trò |
|------|---------|
| **K8s API** | Lưu `podCIDR` và annotation `VtepMAC` / `public-ip` của từng Node |
| **flanneld** (DaemonSet) | Watch API → tạo `flannel.1` (VTEP) → điền bảng Route/ARP/FDB → ghi `subnet.env` |
| **CNI bridge plugin** | Đọc `subnet.env` → tạo veth pair → gắn vào `cni0` → cấp IP cho Pod |

**subnet.env** là "hợp đồng" giữa flanneld và CNI plugin:
```ini
FLANNEL_NETWORK=10.244.0.0/16
FLANNEL_SUBNET=10.244.1.1/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
```

---

## Packet đi qua đâu trên một Node?

```
Pod (eth0: 10.244.X.Y)
      │  veth pair
   cni0  (bridge, gateway: 10.244.X.1)
      │  Kernel routing
 flannel.1  (VTEP, đóng gói VXLAN)
      │  UDP port 8472
   eth0  (physical: 192.168.64.X)
      │
    Mạng vật lý → Node đích
```

**Khi kubelet tạo Pod:**
```
kubelet → 10-flannel.conflist
        → flannel binary (đọc subnet.env)
        → delegate bridge plugin  →  delegate host-local IPAM
```

---

## Kernel định tuyến cross-node bằng 3 bảng tĩnh

Từ `worker1`, gửi packet đến `10.244.2.7` (Pod B trên `worker2`):

```
1. Route table:
   10.244.2.0/24  via 10.244.2.0  dev flannel.1  ← đi qua VTEP

2. ARP table (flannel.1):
   10.244.2.0  →  MAC aa:bb:cc:dd:ee:ff  ← MAC của VTEP worker2

3. FDB table (flannel.1):
   aa:bb:cc:dd:ee:ff  →  dst 192.168.64.12  ← IP vật lý worker2
```

> **flanneld** điền cả 3 bảng này tĩnh từ trước — kernel không cần broadcast hỏi khi có packet.

---

<!-- _class: lab -->

## 🔬 Lab Time

Thực hành theo thứ tự trong `lab-guide.md`:

1. **TN1** — Quan sát cụm trắng: `NotReady`, bảng route trống, chưa có `cni0`/`flannel.1`.
2. **TN2** — Cài Flannel: `kubectl apply`, theo dõi node chuyển `Ready`, card ảo xuất hiện.
3. **TN3** — Đọc K8s API: `podCIDR` từng node, annotation `VtepMAC`/`public-ip`.
4. **TN4** — Đọc `subnet.env`: xem file hợp đồng và `10-flannel.conflist`.
5. **TN5** — Trace Route → ARP → FDB: quan sát flanneld sync real-time.
6. **TN6** — Kiểm chứng: ping cross-node từ pod-a sang pod-b thành công.
7. **Troubleshooting**: 4 sự cố thực chiến — sai `--iface`, mất CNI conflist, chặn UDP 8472, cạn IPAM.

👉 **Làm theo `lab-guide.md`**

---

## Key Takeaways

- **K8s API** giữ nguồn sự thật: `podCIDR` + VTEP MAC + public-ip của từng Node.
- **flanneld** là bộ não: watch API, setup `flannel.1`, điền 3 bảng Route/ARP/FDB tĩnh.
- **CNI bridge plugin** là tay chân: đọc `subnet.env`, cắm veth và cấp IP cho Pod.
- **3 bảng tĩnh** = không cần dynamic discovery khi packet chạy → hiệu quả, đơn giản.

> **Tập tiếp theo:** tcpdump soi gói tin VXLAN thực tế — 50 bytes overhead đến từ đâu?
