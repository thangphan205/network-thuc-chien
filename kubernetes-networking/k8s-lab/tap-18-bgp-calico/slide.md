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

# Tập 18
## BGP trong Calico: Cluster như một Autonomous System, peer với ToR Switch

**Phần 2 — Calico** · `#BGP` `#AS` `#BIRD` `#routing` `#no-encapsulation`

---

## Mục tiêu tập này

- Hiểu khi nào dùng BGP thay vì VXLAN/IPIP
- Cấu hình Calico sang BGP mode (không encapsulation)
- Dùng `calicoctl node status` để xem BGP session
- Verify: routing table thay đổi, tcpdump không còn VXLAN

**Prerequisites:** Cluster Calico từ Tập 11-12 với VXLAN (sẽ chuyển sang BGP)

---

## BGP: Border Gateway Protocol

**Mỗi Node chạy BIRD, quảng bá Pod CIDR của mình:**

```
Datacenter Network:

ToR Switch (AS 65000)         ← Biết về mọi Pod subnet
    │
    ├── Node 1 (AS 64512)     ← Quảng bá: 10.244.1.0/24 ở đây
    │   BIRD peer với ToR
    │
    ├── Node 2 (AS 64512)     ← Quảng bá: 10.244.2.0/24 ở đây
    │
    └── Node 3 (AS 64512)     ← Quảng bá: 10.244.3.0/24 ở đây
```

**Lợi ích:**
- Không có encapsulation overhead (không VXLAN, không IPIP)
- Server bare-metal ngoài cluster ping trực tiếp Pod IP
- Integrate với datacenter network hiện có (standard BGP)

---

## 3 chế độ của Calico

| Chế độ | Encapsulation | Yêu cầu | Dùng khi |
| :--- | :--- | :--- | :--- |
| **VXLAN** | Full VXLAN | Bất kỳ topology | Cloud, multi-subnet |
| **IPIP** | IP-in-IP tunnel | Có IP routing | Datacenter, L3 fabric |
| **BGP (direct)** | Không có | L3 fabric + BGP router | On-prem, cần performance |
| **VXLANCrossSubnet** | VXLAN chỉ khi cross-subnet | Mixed | Datacenter hybrid |

**Lab này:** BGP giữa các Nodes (Node-to-Node BGP, không có ToR switch thật)

---

## Khi nào dùng BGP

```
✅ On-premise datacenter với L3 fabric
✅ Cần server bare-metal access Pod IPs trực tiếp
✅ Performance-sensitive workloads
✅ Team đã quen BGP

❌ Cloud VPC (VPC routing không support custom pod CIDR)
❌ Simple cluster không cần routing integration
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Chuyển sang BGP mode và Verify

Chúng ta sẽ thực hành:

1. **Switch sang BGP:** Patch IP Pool encapsulation từ VXLAN sang None.
2. **Xem BGP sessions:** `calicoctl node status` để verify peering.
3. **Test routing:** Tcpdump confirm không còn UDP 8472 VXLAN traffic.
4. **BGPConfiguration:** Xem AS number và nodeToNodeMeshEnabled.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Full Mesh BGP scale problem — n*(n-1)/2 sessions và Route Reflector giải quyết.
