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

# Tập 8
## VXLAN Backend: Flannel đóng gói packet như thế nào? (50 bytes overhead)

**Phần 1 — Flannel** · `#VXLAN` `#encapsulation` `#tcpdump` `#MTU` `#overhead`

---

## Mục tiêu tập này

- Phân tích cấu trúc VXLAN packet header (50 bytes overhead đến từ đâu)
- Bắt VXLAN traffic bằng `tcpdump` và đọc inner/outer header
- Tính toán MTU thực tế cho payload và hiểu hệ quả TCP MSS
- Giải thích MSS Clamping — cách Flannel tránh fragmentation

**Prerequisites:** Cluster từ Tập 6-7, Flannel VXLAN mode đang chạy

---

## VXLAN: Bọc Ethernet frame vào trong UDP

**Ý tưởng:** Tunnel Layer 2 frame qua Layer 3 UDP — Node nguồn bọc gói, Node đích mở ra.

```
┌──────────────────────────────────────────────────────────────────────┐
│ Outer Eth │ Outer IP │  UDP 8472  │ VXLAN Hdr │ Inner Eth │ Inner IP │ Payload │
│  14 bytes │ 20 bytes │   8 bytes  │  8 bytes  │  14 bytes │ 20 bytes │   ...   │
└──────────────────────────────────────────────────────────────────────┘
            └──────────────── 50 bytes overhead ────────────────────┘
```

**Các trường quan trọng:**
- **Outer IP:** Node nguồn → Node đích (`192.168.64.11 → 192.168.64.12`)
- **UDP port 8472:** Port VXLAN của Linux kernel (khác IANA 4789)
- **VXLAN Header — VNI = 1:** Virtual Network Identifier (Flannel dùng VNI 1)
- **Inner IP:** Pod A → Pod B (`10.244.1.5 → 10.244.2.7`)

---

## MTU: 50 bytes overhead ảnh hưởng thế nào?

```
Physical MTU = 1500 bytes
    └── Outer IP header:    20 bytes  ─┐
    └── UDP header:          8 bytes   │ VXLAN overhead: 50 bytes
    └── VXLAN header:        8 bytes   │
    └── Inner Eth header:   14 bytes  ─┘
    └── Payload available: 1450 bytes  ← MTU thực tế cho Pod

Flannel set MTU = 1450 trên cni0, eth0 của Pod, và flannel.1
```

**Hệ quả TCP MSS:**
- Thông thường: TCP MSS = 1500 - 20 (IP) - 20 (TCP) = **1460 bytes**
- Trong cluster Flannel VXLAN: TCP MSS = 1450 - 20 - 20 = **1410 bytes**
- Mỗi TCP segment nhỏ hơn 50 bytes → cần thêm ~3.4% segments

**MSS Clamping:** Flannel cài iptables rule để tự động ép MSS, tránh fragmentation:
```bash
iptables -t mangle -L | grep TCPMSS
# TCPMSS  tcp  --  anywhere  anywhere  tcp flags:SYN,RST/SYN TCPMSS clamp to PMTU
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Soi packet VXLAN thực tế

Chúng ta sẽ thực hành:

1. **Bắt VXLAN traffic:** Dùng `tcpdump` trên physical interface để thấy outer/inner headers.
2. **Đo MTU thực tế:** Ping với DF bit để xác định giới hạn packet size.
3. **So sánh MTU:** Verify MTU 1450 trên Pod vs 1500 trên physical interface.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

**VXLAN overhead:**
```
Physical MTU: 1500 bytes
  - VXLAN overhead: 50 bytes
  = Effective MTU: 1450 bytes (Pod, bridge, VTEP)

TCP MSS = 1410 bytes (thay vì 1460 thông thường)
→ ~3.4% overhead thêm cho cùng lượng data
```

**Đọc tcpdump VXLAN:**
```
Outer:  192.168.64.11.49152 > 192.168.64.12.8472  ← Node-to-Node
Inner:  10.244.1.5 > 10.244.2.7: ICMP              ← Pod-to-Pod
VNI:    1
```

**Debug VXLAN:**
```bash
tcpdump -i eth0 -n udp port 8472 -v   # Xem VXLAN packets
ip -d link show flannel.1              # VTEP details (VNI, local IP)
ip link show cni0                      # Verify MTU = 1450
```

> **Tập tiếp theo:** host-gw mode — bỏ VXLAN, routing thẳng, không còn 50 bytes overhead!
