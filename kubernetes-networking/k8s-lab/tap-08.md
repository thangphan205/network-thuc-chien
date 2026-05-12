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

- Phân tích cấu trúc VXLAN packet header
- Bắt VXLAN traffic bằng `tcpdump` và xác định inner/outer header
- Tính toán MTU thực tế cho payload
- Giải thích MSS Clamping và cách Flannel xử lý MTU

**Prerequisites:** Cluster từ Tập 6/7, Flannel VXLAN mode đang chạy

---

## VXLAN: Virtual Extensible LAN

**Ý tưởng:** Bọc packet Layer 2 (Ethernet frame) vào trong UDP packet.

```
┌──────────────────────────────────────────────────────────────────────┐
│ Outer Eth │ Outer IP │  UDP 8472  │ VXLAN Hdr │ Inner Eth │ Inner IP │ Payload │
│  14 bytes │ 20 bytes │  8 bytes   │  8 bytes  │  14 bytes │ 20 bytes │   ...   │
└──────────────────────────────────────────────────────────────────────┘
            └─────────────── 50 bytes overhead ────────────────────┘
```

**Các trường quan trọng:**
- **Outer IP:** Node nguồn → Node đích (192.168.64.11 → 192.168.64.12)
- **UDP port 8472:** Port VXLAN của Linux kernel (khác với IANA 4789)
- **VXLAN Header:** VNI = 1 (Virtual Network Identifier)
- **Inner IP:** Pod A → Pod B (10.244.1.5 → 10.244.2.7)

---

## MTU và hậu quả

```
Physical MTU: 1500 bytes
    └── Outer IP header:   20 bytes  ─┐
    └── UDP header:         8 bytes   │ VXLAN overhead: 50 bytes
    └── VXLAN header:       8 bytes   │
    └── Inner Eth header:  14 bytes  ─┘
    └── Payload available: 1450 bytes

Flannel set MTU = 1450 trên cni0 và flannel.1
```

**Hệ quả:**
- TCP MSS = 1450 - 20 (IP) - 20 (TCP) = **1410 bytes** (thay vì 1460 thông thường)
- Flannel tự set MSS Clamping qua iptables để tránh fragmentation:

```bash
# Kiểm tra MSS clamping rule của Flannel
iptables -t mangle -L | grep "TCPMSS"
# TCPMSS  tcp  --  anywhere  anywhere  tcp flags:SYN,RST/SYN TCPMSS clamp to PMTU
```

---

<!-- _class: lab -->

## Lab: Bắt VXLAN với tcpdump

```bash
multipass shell k8s-worker1

# Bắt VXLAN traffic trên physical interface
# VXLAN dùng UDP port 8472 (Linux default, khác IANA 4789)
sudo tcpdump -i eth0 -n udp port 8472 -v &
TCPDUMP_PID=$!

# Tạo traffic cross-node từ master
kubectl exec pod-a -- ping -c 5 <pod-b-ip>

sleep 2
kill $TCPDUMP_PID
```

---

## Lab: Phân tích output tcpdump

```bash
# Output tcpdump sẽ giống như:
# 12:34:56 IP 192.168.64.11.49152 > 192.168.64.12.8472: VXLAN, flags [I] (0x08), vni 1
#           IP 10.244.1.5 > 10.244.2.7: ICMP echo request, id 42, seq 1, length 64

# Outer IP:  192.168.64.11 → 192.168.64.12  (Node-to-Node)
# Inner IP:  10.244.1.5   → 10.244.2.7     (Pod-to-Pod)
# VXLAN VNI: 1

# Bắt với raw hex để thấy bytes thực sự
sudo tcpdump -i eth0 -n udp port 8472 -XX -c 3

# Xem từng layer:
# 0000: [Outer Ethernet] 6B
# 000e: [Outer IP] 20B
# 0022: [UDP] 8B
# 002a: [VXLAN] 8B
# 0032: [Inner Ethernet] 14B
# 0040: [Inner IP] 20B
# 0054: [ICMP payload]
```

---

## Lab: Đo overhead thực tế

```bash
# Test MTU với DF bit (Don't Fragment)
kubectl exec pod-a -- bash -c '
# Ping với packet size tối đa không bị fragment (MTU - 28 bytes ICMP overhead)
# 1450 MTU - 20 IP - 8 ICMP = 1422 bytes data

# Thử size OK
ping -c 3 -s 1422 -M do <pod-b-ip>
# 3 packets transmitted, 3 received ✅

# Thử size vượt MTU (1451 payload)
ping -c 3 -s 1451 -M do <pod-b-ip>
# ping: local error: message too long, mtu=1450
# → Kernel từ chối gửi vì DF=1 và size > MTU
'

# So sánh MTU trong Pod vs trên Node
kubectl exec pod-a -- ip link show eth0
# eth0: mtu 1450  ← Pod MTU (Flannel set)

multipass exec k8s-worker1 -- ip link show eth0
# eth0: mtu 1500  ← Physical MTU

multipass exec k8s-worker1 -- ip link show cni0
# cni0: mtu 1450  ← Bridge MTU (khớp với Pod)

multipass exec k8s-worker1 -- ip link show flannel.1
# flannel.1: mtu 1450  ← VTEP MTU
```

---

## Lab: Xem FDB và ARP của VTEP

```bash
# FDB (Forwarding Database) — biết VTEP MAC nào ở Node nào
bridge fdb show dev flannel.1
# 00:00:00:00:00:00 dst 192.168.64.10 self permanent  ← Broadcast đến master
# aa:bb:cc:dd:ee:ff dst 192.168.64.12 self permanent  ← Unicast đến worker2

# ARP của flannel.1 — inner Pod gateway MACs
ip neigh show dev flannel.1
# 10.244.0.0 lladdr aa:bb:cc:.. PERMANENT  ← Gateway master subnet
# 10.244.2.0 lladdr cc:dd:ee:.. PERMANENT  ← Gateway worker2 subnet

# Khi gửi đến 10.244.2.7:
# 1. Route: 10.244.2.0/24 via 10.244.2.0 dev flannel.1
# 2. ARP:   10.244.2.0 → MAC cc:dd:ee (VTEP MAC của worker2)
# 3. FDB:   cc:dd:ee → 192.168.64.12 (IP Node của worker2)
# 4. Tạo outer UDP 8472 packet đến 192.168.64.12
```

---

## Key Takeaways

**VXLAN overhead:**
```
Physical MTU 1500
  - VXLAN overhead 50 bytes
  = Payload 1450 bytes effective MTU

TCP MSS = 1410 bytes (thay vì 1460 thông thường)
→ Mỗi TCP segment nhỏ hơn 50 bytes
→ Cần thêm ~3.4% segments để truyền cùng data
```

**Debug VXLAN:**
```bash
tcpdump -i eth0 -n udp port 8472 -v    # Xem VXLAN packets
bridge fdb show dev flannel.1           # VTEP MAC mapping
ip neigh show dev flannel.1             # Inner IP to MAC
ip -d link show flannel.1               # VTEP details (VNI, local IP)
```

> **Tập tiếp theo:** host-gw mode — bỏ VXLAN, dùng routing thẳng để giảm overhead!
