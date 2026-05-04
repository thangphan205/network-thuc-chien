---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', 'Noto Sans', sans-serif;
    font-size: 22px;
    background: linear-gradient(135deg, #1d4ed8 0%, #1e3a8a 100%);
    color: #ffffff;
  }
  h1 { color: #ffd700 !important; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #ffffff; font-size: 1.4em; border-bottom: 2px solid #ffd700; padding-bottom: 0.2em; }
  h3 { color: #e0e7ff; font-size: 1.1em; }
  strong { color: #fbbf24; }
  code { background: #1e3a8a; color: #86efac; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1e3a8a; border-left: 4px solid #ffd700; padding: 16px; border-radius: 6px; }
  pre code { color: #86efac; background: transparent; padding: 0; }
  .hljs-keyword, .hljs-selector-tag { color: #ff79c6; }
  .hljs-string, .hljs-addition { color: #f1fa8c; }
  .hljs-attr, .hljs-attribute { color: #93c5fd; }
  .hljs-number, .hljs-literal { color: #c4b5fd; }
  .hljs-comment { color: #93c5fd; font-style: italic; }
  .hljs-variable, .hljs-template-variable { color: #fcd34d; }
  .hljs-built_in, .hljs-name, .hljs-type { color: #86efac; }
  .hljs-meta { color: #fca5a5; }
  .hljs-bullet, .hljs-symbol { color: #fcd34d; }
  .hljs-params, .hljs-subst { color: #ffffff; }
  .hljs-deletion { color: #fca5a5; }
  .hljs-title, .hljs-section { color: #bfdbfe; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  th { background: #1e3a8a; color: #ffd700; padding: 10px 14px; font-weight: 600; letter-spacing: 0.03em; }
  td { padding: 8px 14px; border-bottom: 1px solid #3b82f6; color: #ffffff; background: #2563eb; }
  tr:nth-child(even) td { background: #1d4ed8; }
  tr:hover td { background: #1e40af; }
  blockquote { border-left: 4px solid #ffd700; padding-left: 16px; color: #e0e7ff; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  section.title {
    background: linear-gradient(135deg, #1d4ed8 0%, #1e3a8a 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
    padding: 60px 80px;
  }
  section.title h1 { font-size: 2.8em; color: #ffd700 !important; border: none; }
  section.title h2 { font-size: 1.3em; color: #ffffff; border: none; margin-top: 0.2em; }
  section.title p { color: #bfdbfe; font-size: 0.9em; margin-top: 16px; }
  section.divider {
    background: linear-gradient(135deg, #1e3a8a 0%, #1d4ed8 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    text-align: center;
  }
  section.divider h1 { font-size: 2.5em; border: none; color: #ffd700 !important; }
  section.divider h2 { border: none; color: #ffffff; }
  a { color: #ffd700; text-decoration: underline; }
  .good { color: #86efac; font-weight: bold; }
  .bad  { color: #fca5a5; font-weight: bold; }
  .warn { color: #fcd34d; font-weight: bold; }
---

<!-- _class: title -->

# 🌐 Tập 1: Network Model & Pod
## Lý thuyết: 4 Nguyên tắc không NAT, Pause Container & veth pair

**Network Thực Chiến** · Series: Kubernetes Networking · Tập 01

---

## 📋 Nội dung

1. **Kubernetes Network Model** — Tờ khế ước 4 nguyên tắc bất biến
2. **Pause Container** — "Cái giá đỡ mạng" ẩn mình trong mọi Pod
3. **veth pair** — Cầu nối giữa Pod và Node
4. **Kiểm tra thực tế** — `ip netns`, `nsenter`, `crictl`

---

<!-- _class: divider -->

# 🔬 Phần 1
## Kubernetes Network Model

---

## Tờ khế ước nền tảng

K8s không quy định bạn phải dùng công nghệ mạng nào. Nhưng nó đặt ra **4 nguyên tắc bất biến** mà bất kỳ CNI plugin nào cũng phải tuân thủ:

1. **Pod-to-Pod không NAT**: Mọi Pod đều có thể giao tiếp với mọi Pod khác trên bất kỳ Node nào mà **không cần NAT**.
2. **Node-to-Pod không NAT**: Node có thể liên lạc trực tiếp với bất kỳ Pod nào mà không cần NAT.
3. **IP của Pod là cố định**: IP mà Pod tự "nhìn thấy" bản thân (`eth0` bên trong Pod) phải là **đúng IP** mà các Pod khác dùng để liên lạc với nó.
4. **Mọi Pod có IP riêng**: Không có chuyện 2 Pod chia sẻ cùng 1 IP.

---

## Flat Network Model

```
Node 1 (192.168.1.10)           Node 2 (192.168.1.11)
┌────────────────────────┐      ┌────────────────────────┐
│  Pod A: 10.244.0.5     │      │  Pod C: 10.244.1.3     │
│  Pod B: 10.244.0.6     │      │  Pod D: 10.244.1.4     │
└────────────────────────┘      └────────────────────────┘
          │                                  │
          └──────────── CNI Plugin ──────────┘
                   (Flannel / Calico / Cilium)

Pod A (10.244.0.5) → Pod C (10.244.1.3)
  ✅ Đi thẳng — KHÔNG qua NAT
  ✅ Source IP giữ nguyên là 10.244.0.5
```

> Đây là lý do mọi CNI plugin đều implement Overlay (VXLAN/IPIP) hoặc BGP routing — để đảm bảo tính no-NAT.

---

## Tại sao no-NAT quan trọng?

| Scenario | Với NAT | Không NAT (K8s model) |
| :--- | :--- | :--- |
| App log source IP | ❌ Log thấy IP Node, không phải Pod | ✅ Log thấy IP Pod thực |
| Distributed tracing | ❌ Trace bị đứt đoạn tại NAT | ✅ Trace xuyên suốt |
| Firewall rule | ❌ Phải rule cho từng Node IP | ✅ Rule theo Pod IP/subnet |
| Service discovery | ❌ Cần thêm layer discovery | ✅ DNS → Pod IP thẳng |

---

<!-- _class: divider -->

# ⏸️ Phần 2
## Pause Container

---

## Pause Container là gì?

Mỗi Pod trong K8s thực chất chứa **ít nhất 2 containers**:

```
Pod: my-app
├── pause container (infra container)   ← Ẩn, không thấy trong kubectl
│     └── Giữ Network Namespace
│     └── Giữ IPC Namespace
│     └── PID = 1 (tránh zombie process)
└── my-app container                    ← Container bạn tạo ra
      └── JOIN vào Network NS của pause
```

> `pause` container image siêu nhỏ (~700KB), chỉ chạy 1 syscall: `pause()`.
> Nó là **"cái giá đỡ"** giữ Network Namespace tồn tại ngay cả khi app container restart.

---

## Tại sao cần Pause Container?

**Vấn đề:** Nếu không có pause, Network NS sẽ biến mất khi container restart.

```
Không có pause:
  App crash → Container bị xóa → Network NS biến mất
  → Pod IP thay đổi → Service discovery sai!

Có pause:
  App crash → Container restart (pause vẫn sống)
  → Network NS GIỮ NGUYÊN → Pod IP KHÔNG ĐỔI ✅
```

**Kiểm tra pause container đang chạy:**
```bash
# Trên worker node (cần ssh vào)
sudo crictl ps | grep pause
# CONTAINER   IMAGE    CREATED   STATE    NAME    POD ID
# abc123      pause    5m        Running  pause   xyz789...
```

---

## veth pair: Cầu nối Pod ↔ Node

```
┌─── Pod Network Namespace ───┐    ┌─── Host Network Namespace ───┐
│                             │    │                              │
│  eth0 (10.244.0.5)          │    │  cali3a8f2b4c (Node side)    │
│  ↑ Bên trong Pod thấy nó    │    │  ↑ Trên Node, `ip link show` │
│                             │    │                              │
└─────────────────────────────┘    └──────────────────────────────┘
         └──────── veth pair ────────┘
              (Virtual Ethernet)
```

**veth pair hoạt động như dây cáp ảo:**
- Một đầu trong Pod (gọi là `eth0`)
- Một đầu ngoài Node (gọi là `cali...`, `veth...`)
- Packet vào một đầu → **ngay lập tức xuất hiện** ở đầu kia

---

## ⚠️ "Namespace" — 2 khái niệm hoàn toàn khác nhau

Cùng 1 từ, 2 tầng kỹ thuật khác nhau — đây là nguồn gốc nhầm lẫn phổ biến nhất:

| | **Kubernetes Namespace** | **Linux Network Namespace** |
| :--- | :--- | :--- |
| **Là gì** | Phân vùng logic cho K8s resources | Cô lập kernel: interfaces, routing table, iptables |
| **Lệnh** | `kubectl get ns` · `kubectl -n prod` | `ip netns list` · `ip netns exec` |
| **Tạo bởi** | Admin/Dev (`kubectl create namespace`) | CNI plugin (tự động khi Pod được schedule) |
| **Cô lập mạng?** | ❌ Không — chỉ cô lập resource view | ✅ Có — Pod có riêng eth0, routing table, iptables |

```
K8s Namespace "production":            Linux Network Namespace (của Pod):
  kubectl -n production get pods    ←→  /var/run/netns/cni-abc12345-...
  ↑ Gom nhóm resources cho dễ quản lý   ↑ Cô lập kernel thật sự
  ↑ Pod khác namespace vẫn ping được    ↑ Pod có ip riêng, route riêng, iptables riêng
```

> **Quy tắc nhớ:** Nói về **Pod networking** (IP, route, interface) → luôn là **Linux Network Namespace**.
> Nói về `kubectl -n`, phân quyền, resource isolation → luôn là **Kubernetes Namespace**.

---

<!-- _class: divider -->

# 🔧 Phần 3
## Kiểm tra thực tế

---

## ip netns: Xem Network Namespaces

```bash
# Trên worker node — liệt kê tất cả network namespaces
sudo ip netns list
# cni-abc12345-1234-5678-abcd-123456789012 (id: 5)
# cni-def67890-...

# Chạy lệnh trong một namespace cụ thể
sudo ip netns exec cni-abc12345-... ip addr show
# 1: lo: <LOOPBACK,UP> ...
# 2: eth0@if7: <BROADCAST,UP> mtu 1450 ...
#    inet 10.244.0.5/32 scope global eth0

# Xem veth pair: số sau "@if" là index của đầu bên Node
sudo ip link show | grep "^7:"
# 7: cali3a8f2b4c@if2: <BROADCAST,UP> ...
```

---

## nsenter: Chui vào Pod Network NS

```bash
# Lấy PID của pause container của Pod
POD="my-app-xxx"
PAUSE_ID=$(kubectl get pod $POD \
  -o jsonpath='{.status.containerStatuses[0].containerID}' \
  | sed 's/containerd:\/\///')
PID=$(sudo crictl inspect $PAUSE_ID \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['pid'])")

# Chui vào network namespace, dùng tools từ Node
sudo nsenter -t $PID -n ip addr show
sudo nsenter -t $PID -n ip route show
sudo nsenter -t $PID -n ss -tlnp
```

> Hữu ích khi cần debug Pod không có tools (`distroless` image).

---

## Key Takeaways

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **4 nguyên tắc K8s** | No-NAT Pod-to-Pod, no-NAT Node-to-Pod, IP cố định, IP riêng |
| **Pause container** | Giữ Network NS ngay cả khi app container restart |
| **veth pair** | "Dây cáp ảo" nối Pod NS với Host NS |
| **K8s Namespace** | Phân vùng logic resources — `kubectl -n` — KHÔNG cô lập mạng |
| **Linux Network Namespace** | Cô lập kernel thật sự — `ip netns` — tạo ra mạng riêng cho Pod |
| **nsenter** | Dùng tools của Node để debug network trong Pod |

---

<!-- _class: title -->

# Cảm ơn đã theo dõi! 🙏

**Network Thực Chiến**

Tập tiếp theo: **Tập 2 — CNI Specification: Cơ chế plugin hoạt động**

> *"K8s không quan tâm bạn dùng mạng gì — miễn là không có NAT."*
