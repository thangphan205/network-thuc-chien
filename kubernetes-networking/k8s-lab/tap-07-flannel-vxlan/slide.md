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

# Tập 7 - Flannel - VXLAN
## VXLAN Backend: Flannel đóng gói packet như thế nào? (50 bytes overhead)

**Phần 1 — Flannel** · `#VXLAN` `#encapsulation` `#tcpdump` `#MTU` `#overhead`
![height:200px](https://github.com/flannel-io/flannel/blob/master/logos/flannel-horizontal-color.png?raw=true)

---

## Mục tiêu tập này

- Phân tích cấu trúc VXLAN packet — 50 bytes overhead đến từ đâu.
- Bắt VXLAN traffic bằng `tcpdump`, đọc outer/inner header và VNI.
- Hiểu MTU 1450 của Pod và TCP MSS tự đàm phán.
- Chẩn đoán và sửa lỗi **MTU Black Hole** — bệnh kinh điển của môi trường Overlay.

**Prerequisites:** Cluster từ Tập 6 với Flannel VXLAN mode đang chạy.

---

## VXLAN đóng gói: Cấu trúc packet trên dây

```
Outer Ethernet  14b  ← L2 frame, NIC xử lý, KHÔNG tính vào MTU 1500
━━━━━━━━━━━━━━━━━━━━━━ 1500 bytes MTU bắt đầu từ đây ━━━━━━━━━━━━━━━━━━━━
Outer IP        20b  ← 192.168.64.11 → 192.168.64.12  (Node-to-Node)
UDP port 8472    8b  ← Cổng VXLAN Linux kernel
VXLAN Header     8b  ← VNI = 1  (Virtual Network Identifier)
━━━━━━━━━━━━━━━━━━━━━━━ 50 bytes overhead ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Inner Ethernet  14b  ← VTEP MAC nguồn → VTEP MAC đích
Inner IP        20b  ← 10.244.1.5 → 10.244.2.7        (Pod-to-Pod)
Payload        ...b  ← Dữ liệu thực sự của ứng dụng
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> **tcpdump** trên `eth0` của Node sẽ thấy **cả 2 tầng**: outer IP (node) và inner IP (pod) trong cùng 1 gói.

---

## MTU: 50 bytes overhead bị trừ ở đâu?

```
Physical MTU = 1500 bytes
  − Outer IP   20b  ┐
  − UDP         8b  ├─ VXLAN overhead = 50 bytes
  − VXLAN Hdr   8b  │
  − Inner Eth  14b  ┘
  ─────────────────────
  = 1450 bytes  ← MTU thực tế của Pod
```

**Tại sao Outer Ethernet (14b) không bị trừ?**
MTU là khái niệm **L3** — đo kích thước IP packet. Outer Ethernet là L2 framing, NIC xử lý transparent, không tính vào MTU.

**Flannel tự set MTU = 1450** trên `cni0`, `eth0` của Pod, và `flannel.1`.

---

## TCP MSS: Pod tự tránh fragmentation

| | Thông thường | Flannel VXLAN |
|---|---|---|
| MTU interface | 1500 bytes | **1450 bytes** |
| TCP MSS | 1500 − 20 − 20 = **1460** | 1450 − 20 − 20 = **1410** |
| Overhead | — | Thêm ~3.4% segments |

**Cách tự xử lý:**
1. Pod gửi TCP SYN → TCP stack đọc MTU interface = 1450 → tính MSS = 1410
2. Ghi MSS = 1410 vào gói SYN gửi đến server
3. Server cam kết chỉ gửi packet ≤ 1410 bytes payload
4. Packet ra host + 50b VXLAN wrap = đúng 1500b → trơn tru, không bao giờ bị phân mảnh

> Flannel **không dùng iptables MSS Clamping** — TCP stack trong Pod tự đàm phán qua MTU.

---

<!-- _class: lab -->

## 🔬 Lab Time: Soi packet VXLAN thực tế

Thực hành theo thứ tự trong file `lab-guide.md`:

1. **TN1** — Bắt VXLAN traffic (3 terminal song song): `tcpdump` trên `eth0`, xem VNI, đọc outer/inner headers.
2. **TN2** — Chứng minh 50 bytes: ping payload 64b cố định → `length` outer − inner = **50**.
3. **TN3** — Đo MTU bằng DF bit: `-s 1422 -M do` pass, `-s 1423 -M do` lỗi `message too long, mtu=1450`.
4. **TN4** — Benchmark iperf3: đo throughput VXLAN 30 giây, ghi baseline so sánh với host-gw Tập 8.
5. **Troubleshooting — MTU Black Hole**: ping nhỏ thông, HTTP/gRPC lớn treo → xác định MTU thật, sửa `kube-flannel-cfg`.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

- **50 bytes overhead** = Outer IP (20) + UDP (8) + VXLAN Header (8) + Inner Ethernet (14).
- **MTU Pod = 1450** — Flannel set tự động để nhường chỗ cho 50 bytes wrapper.
- **TCP MSS = 1410** — Pod tự đàm phán trong SYN handshake, không cần can thiệp thêm.
- **MTU Black Hole**: xảy ra khi MTU vật lý host < 1500 nhưng Flannel không biết → packet lớn bị drop âm thầm.

```bash
tcpdump -i eth0 -n udp port 8472 -v   # Outer: node IP, Inner: pod IP, VNI
ip -d link show flannel.1              # VTEP details (VNI, local IP, MTU)
ip link show cni0                      # Verify MTU = 1450
```

> **Tập tiếp theo:** host-gw mode — bỏ VXLAN, routing thẳng, không còn 50 bytes overhead!
