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

# Tập 20
## WireGuard trong Calico: Mã hóa traffic nội bộ & bẫy MTU 1440 bytes

**Phần 2 — Calico** · `#WireGuard` `#encryption` `#MTU` `#PMTUD` `#security`

---

## Mục tiêu tập này

- Bật WireGuard encryption cho Pod-to-Pod traffic
- Tính toán MTU đúng với WireGuard overhead
- Reproduce PMTUD Black Hole và fix
- Hiểu khi nào cần WireGuard vs không cần

**Prerequisites:** Cluster Calico, Ubuntu 26.04 (kernel 6.x — WireGuard được build sẵn)

---

## Tại sao cần WireGuard?

**Mặc định:** Pod-to-Pod traffic đi qua mạng nội bộ **không được mã hóa**.

```
Scenario nguy hiểm:
Node 1 → [Network switch] → Node 2
         Packet không mã hóa!

Nếu ai đó có thể sniff switch:
tcpdump -i eth0 → thấy toàn bộ Pod traffic
```

**WireGuard giải quyết:**
- Mã hóa toàn bộ Pod-to-Pod traffic (inter-node)
- Kernel-native (không cần userspace daemon)
- Modern crypto: Curve25519, ChaCha20, BLAKE2s
- Key rotation tự động

---

## WireGuard MTU Overhead

```
Physical MTU: 1500 bytes

WireGuard overhead breakdown:
├── IP header:              20 bytes
├── UDP header:              8 bytes
├── WireGuard static header: 4 bytes
└── WireGuard auth tag:     16 bytes
                          ─────────
Total WireGuard overhead:  48 bytes

Effective MTU: 1500 - 48 = 1452 bytes

Calico WireGuard default MTU: 1420 bytes (buffer thêm 32 bytes)
```

**PMTUD Black Hole:**
```
TCP segment size > 1420 bytes + DF bit = 1 (Don't Fragment)
→ Router muốn fragment nhưng không được (DF=1)
→ Router DROP packet SILENTLY (không gửi ICMP fragmentation needed)
→ TCP sender không biết → không reduce MSS → hang mãi
→ Small files OK (fit trong 1420), large files FAIL
```

---

<!-- _class: lab -->

## Lab: Bật WireGuard trên Calico

```bash
multipass shell k8s-master

# Kiểm tra WireGuard module (Ubuntu 26.04 có sẵn)
multipass exec k8s-worker1 -- sudo modprobe wireguard && echo "WireGuard OK"
# WireGuard OK

# Bật WireGuard encryption cho Calico
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardEnabled": true}}'

# Verify: Interface wireguard.cali xuất hiện
multipass exec k8s-worker1 -- ip link show wireguard.cali
# wireguard.cali: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc ...

# Xem WireGuard public key của node
multipass exec k8s-worker1 -- sudo wg show wireguard.cali
# interface: wireguard.cali
#   public key: xxxxx=
#   listening port: 51820
#   peers: 2    ← Peer với 2 nodes khác
```

---

## Lab: Verify encryption đang hoạt động

```bash
# Bắt traffic giữa 2 nodes — không còn readable plain text
multipass exec k8s-worker1 -- sudo tcpdump -i eth0 -n udp port 51820 -X -c 5

# Output: thấy UDP packets nhưng payload là gibberish (encrypted)
# 0x0000: xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx
# ← Không đọc được nội dung!

# So sánh với không có WireGuard (ping thấy ICMP plaintext)
# kubectl exec pod-a -- ping → tcpdump thấy ICMP rõ ràng

# WireGuard stats
multipass exec k8s-worker1 -- sudo wg show wireguard.cali transfer
# peer: xxx=
#   transfer: 1.45 KiB received, 1.23 KiB sent  ← Traffic đã qua WireGuard
```

---

## Lab: Reproduce PMTUD Black Hole

```bash
# Đặt MTU sai (quá cao) để trigger Black Hole
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardMTU": 1500}}'  # Sai! Phải là 1420

# Tạo file lớn để test
kubectl exec pod-a -- dd if=/dev/urandom of=/tmp/largefile bs=1M count=5

# Thử transfer file lớn qua nc
kubectl exec pod-b -- nc -lk -p 9999 > /dev/null &
kubectl exec pod-a -- nc -w 5 <pod-b-ip> 9999 < /tmp/largefile
# (Hang! không hoàn thành) ← PMTUD Black Hole!

# Diagnose với ping DF bit
kubectl exec pod-a -- ping -s 1440 -M do <pod-b-ip>
# PING: local error: message too long, mtu=1420
# ← Kernel report MTU mismatch

# Fix: Set MTU đúng
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardMTU": 1420}}'

# Test lại sau fix
kubectl exec pod-a -- nc -w 10 <pod-b-ip> 9999 < /tmp/largefile
# (Hoàn thành trong vài giây) ✅
```

---

## Lab: MSS Clamping — fix tại TCP layer

```bash
# MSS Clamping: buộc TCP handshake advertise MSS nhỏ hơn
# Cách Calico bật MSS clamping
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardMssClamp": 1380}}'
# 1380 = 1420 (WireGuard MTU) - 20 (IP) - 20 (TCP) = 1380 MSS

# Verify iptables rule được tạo
multipass exec k8s-worker1 -- sudo iptables -t mangle -L | grep TCPMSS
# TCPMSS  tcp  --  anywhere  anywhere  tcp flags:SYN,RST/SYN TCPMSS clamp to 1380
# ← Calico tự set MSS Clamping cho WireGuard!
```

---

## Key Takeaways

**WireGuard trong Calico:**
```
Bật: kubectl patch felixconfiguration default --patch '{"spec":{"wireguardEnabled":true}}'
MTU: 1420 bytes (1500 - 80 bytes buffer)
Port: UDP 51820
Key: Tự generate + rotate

Khi nào cần:
✅ Multi-tenant cluster
✅ Compliance yêu cầu encryption in-transit
✅ Traffic qua untrusted network
✅ Multi-DC, hybrid cloud

Khi nào không cần:
❌ Single-tenant, trusted network (overhead không đáng)
❌ Cluster trong private datacenter với physical security
```

**MTU trap:**
```
WireGuard overhead: ~48-80 bytes
Calico default MTU: 1420 (safe)
PMTUD Black Hole: file nhỏ OK, file lớn fail
Fix: wireguardMTU: 1420 + MSS Clamping
```

> **Tập tiếp theo:** Troubleshooting Calico — workflow debug từ calicoctl đến ip route đến iptables.
