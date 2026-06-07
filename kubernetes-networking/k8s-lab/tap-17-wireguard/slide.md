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
  section.warn { background: linear-gradient(135deg, #1a0800 0%, #0d1021 100%); }
  section.warn h2 { color: #f87171; border-bottom-color: #f87171; }
---

<!-- _class: ep -->

# Tập 17
## WireGuard trong Calico: Mã hóa traffic nội bộ & bẫy MTU 1440 bytes

**Phần 2 — Calico** · `#WireGuard` `#encryption` `#MTU` `#PMTUD` `#security`

---

## Mục tiêu tập này

- Bật WireGuard encryption cho Pod-to-Pod traffic
- Tính toán MTU đúng với WireGuard overhead
- Reproduce PMTUD Black Hole và fix
- Hiểu khi nào cần WireGuard vs không cần

**Prerequisites:** Cluster Calico, Ubuntu 26.04 (kernel 6.x/7.x+ — WireGuard được build sẵn)

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

WireGuard overhead:
├── IP header:              20 bytes
├── UDP header:              8 bytes
├── WireGuard static header: 4 bytes
└── WireGuard auth tag:     16 bytes
                          ─────────
Total:                     48 bytes

Effective MTU: 1500 - 48 = 1452 bytes

Calico WireGuard default MTU: 1420 bytes (buffer thêm)
Port: UDP 51820
```

---

<!-- _class: warn -->

## PMTUD Black Hole — Bẫy MTU ẩn

```
TCP segment size > 1420 bytes + DF bit = 1 (Don't Fragment)
→ Router muốn fragment nhưng không được (DF=1)
→ Router DROP packet SILENTLY (không gửi ICMP fragmentation needed)
→ TCP sender không biết → không reduce MSS → hang mãi

Triệu chứng:
  Small files: OK (fit trong 1420 bytes)
  Large files: FAIL (hang, không báo lỗi rõ)
```

**Fix:**
```
1. Set wireguardMTU: 1420 (đúng overhead)
2. MSS Clamping: ép TCP negotiate MSS ≤ 1380
```

---

## Khi nào cần WireGuard

```
✅ Multi-tenant cluster
✅ Compliance yêu cầu encryption in-transit
✅ Traffic qua untrusted network (multi-DC)
✅ Hybrid cloud

❌ Single-tenant, trusted private datacenter (overhead không đáng)
❌ Cluster với physical network security (isolation đã đảm bảo)
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Bật WireGuard và Fix MTU

Chúng ta sẽ thực hành:

1. **Kiểm tra WireGuard module:** Ubuntu 26.04 có sẵn trong kernel.
2. **Bật WireGuard:** Patch FelixConfiguration, verify `wireguard.cali` interface xuất hiện.
3. **Verify encryption:** Tcpdump thấy UDP 51820 với payload gibberish (encrypted).
4. **Reproduce PMTUD Black Hole:** Set MTU sai, file lớn hang, diagnose, fix.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## 🔧 Troubleshooting WireGuard & MTU — Tóm tắt

| Triệu chứng | Công cụ điều tra | Nguyên nhân & Cách xử lý |
| :--- | :--- | :--- |
| `wireguard.cali` không xuất hiện | `lsmod \| grep wireguard` | Kernel chưa load WireGuard module; chạy `modprobe wireguard` |
| Bật WireGuard nhưng traffic không mã hóa | `sudo wg show wireguard.cali` | `wireguardEnabled` chưa được set thành `true` trong FelixConfig |
| Gửi file lớn bị treo (PMTUD Black Hole) | `ping -s 1440 -M do <IP>` | MTU đặt quá cao (1500) hoặc thiếu MSS Clamping; sửa `wireguardMTU: 1420` |
| Lỗi CNI khi pod khởi động | `kubectl describe pod` | Felix chưa cấu hình xong MTU; khởi động lại calico-node DaemonSet |

**Quy tắc debug:** Kiểm tra tầng Kernel (modprobe) → Kiểm tra config Calico (FelixConfig) → Kiểm tra Data Plane (iptables mangle & tcpdump UDP 51820).

---

> **Tập tiếp theo:** Troubleshooting Calico — workflow debug từ calicoctl đến ip route đến iptables.
