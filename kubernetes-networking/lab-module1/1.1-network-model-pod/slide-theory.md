---
marp: true
theme: gaia
_class: lead
paginate: true
backgroundColor: #0f172a
color: #e2e8f0
---

<style>
h1 { color: #38bdf8; font-size: 1.6em; }
h2 { color: #7dd3fc; }
h3 { color: #bae6fd; }
strong { color: #fbbf24; }
code { background: #1e293b; color: #86efac; padding: 2px 6px; border-radius: 4px; }
blockquote { border-left: 4px solid #38bdf8; color: #94a3b8; padding-left: 1em; }
table { font-size: 0.8em; }
th { background: #1e40af; color: white; }
td { background: #1e293b; }
pre { background: #1e293b; font-size: 0.75em; }
</style>

# **Tập 1: Network Model & Pod**
### Lý thuyết: 4 Nguyên tắc không NAT, Pause Container & veth pair

**Thang** | @NetworkThucChien

---

# Kubernetes Network Model: Tờ khế ước nền tảng

K8s không quy định bạn phải dùng công nghệ mạng nào. Nhưng nó đặt ra **4 nguyên tắc bất biến** mà bất kỳ CNI plugin nào cũng phải tuân thủ:

1. **Pod-to-Pod không NAT**: Mọi Pod đều có thể giao tiếp với mọi Pod khác trên bất kỳ Node nào mà **không cần NAT**.
2. **Node-to-Pod không NAT**: Node có thể liên lạc trực tiếp với bất kỳ Pod nào mà không cần NAT.
3. **IP của Pod là cố định**: IP mà Pod tự "nhìn thấy" bản thân (`eth0` bên trong Pod) phải là **đúng IP** mà các Pod khác dùng để liên lạc với nó.
4. **Mọi Pod có IP riêng**: Không có chuyện 2 Pod chia sẻ cùng 1 IP.

---

# Tại sao "Không NAT" lại quan trọng?

Hãy nhớ lại kiến trúc cũ với Docker (trước K8s):

```
Container A (172.17.0.2)
    ↓ NAT (SNAT → IP của Host)
  Host A (192.168.1.10)
    ↓ Network
  Host B (192.168.1.11)
    ↓ NAT (DNAT → IP Container)
Container B (172.17.0.3)
```

**Vấn đề:** Container B nhìn thấy IP nguồn là `192.168.1.10` (IP Host A) thay vì IP thực của Container A. Điều này gây ra vô vàn khó khăn cho Security, Logging và Service Discovery.

---

# K8s giải quyết bằng "Flat Network"

```
Pod A (10.244.1.5)          Pod B (10.244.2.8)
    │                              │
    └─────────── Reach directly ──►│
          (Không cần NAT!)
```

Mọi Pod đều thuộc **một mạng phẳng chung** (Flat Network). CNI plugin có nhiệm vụ **đục đường hầm** (Overlay) hoặc **thêm route** (Underlay) để đảm bảo điều này.

> **Đây là lý do tồn tại của CNI.** Không có CNI, không có Flat Network, K8s sẽ không hoạt động.

---

# 🔬 Pause Container - Kiến trúc ngầm của Pod

Khi bạn tạo một Pod với 2 containers (app + sidecar), thực tế bên trong Node có **3 container** được tạo ra:

```
Pod: my-app
├── pause container (infracontainer)  ← BÍ MẬT!
├── app container
└── sidecar container
```

**Pause container** là container siêu nhỏ (~700KB) được tạo ra **đầu tiên**. Nó giữ vai trò là **"chủ nhân" của Network Namespace** cho toàn bộ Pod.

---

# Pause Container hoạt động ra sao?

```
┌─────────────────── Pod: my-app ────────────────────┐
│                                                      │
│  pause (PID 1)  ←─── Giữ Network Namespace          │
│       │                (eth0, IP, iptables rules)   │
│       │                                              │
│  ┌────┴─────┐    ┌──────────────┐                  │
│  │   app    │    │   sidecar    │                  │
│  │container │    │  container   │                  │
│  │(net=pod) │    │(net=pod)     │                  │
│  └──────────┘    └──────────────┘                  │
│                                                      │
│  Tất cả chia sẻ: eth0, 127.0.0.1, port space      │
└─────────────────────────────────────────────────────┘
```

Các app container **join vào** Network Namespace của pause container, chứ không tạo Network Namespace riêng.

---

# 🔌 veth pair - Dây cáp ảo kết nối Pod vào Node

CNI tạo ra một cặp interface ảo (**virtual ethernet pair**) khi gắn Pod vào mạng:

```
┌── Worker Node ─────────────────────────────────────┐
│                                                      │
│  ┌── Pod Namespace ──┐     ┌── Root Namespace ──┐  │
│  │                    │     │                     │  │
│  │  eth0 (Pod IP)  ◄──┼─────┼► veth3a8f2b        │  │
│  │                    │     │       │             │  │
│  └────────────────────┘     │   cni0 bridge       │  │
│                              │       │             │  │
│                              │    eth0 (Node IP)   │  │
│                              └─────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

**veth pair** hoạt động như một **dây cáp ảo**: gói tin đi vào một đầu sẽ ra ngay đầu còn lại. Đây là cơ chế nền tảng của mọi CNI plugin.

---

# Kiểm chứng trên Node thực tế

Sau khi tạo một Pod, bạn có thể xem veth pair từ Node:

```bash
# Trên Worker Node, liệt kê tất cả interface
ip link show

# Bạn sẽ thấy các interface dạng:
# veth3a8f2b@if3: ...  ← Một đầu của veth pair (trên Node)
# vethab12cd@if5: ...  ← Đầu kia (trong Pod)

# Xem route table của Node để thấy K8s thêm route đến Pod IP:
ip route show
# 10.244.1.5 dev veth3a8f2b scope link  ← Route đến Pod A
# 10.244.2.0/24 via 192.168.56.11 dev eth1  ← Route đến Node 2
```

---

# Tổng kết Tập 1

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **4 nguyên tắc không NAT** | Mọi Pod giao tiếp trực tiếp bằng IP thật, không qua NAT |
| **Flat Network** | Tất cả Pod thuộc một dải mạng phẳng, mọi Pod reach được mọi Pod |
| **Pause Container** | "Người giữ nhà" Network Namespace cho toàn bộ Pod |
| **veth pair** | Dây cáp ảo 2 đầu kết nối Pod Namespace vào Root Namespace của Node |

> **Bài Lab 1.1:** Hãy tự tay inspect những thứ này trên cluster thực tế của bạn!

---

# 👉 Chuyển sang Lab 1.1

Mở file **`lab-guide.md`** trong thư mục `1.1/` để thực hành các thao tác:
- Xem `pause` container bằng `crictl`
- Tìm veth pair của Pod
- Chui vào Network Namespace của Pod từ Node
