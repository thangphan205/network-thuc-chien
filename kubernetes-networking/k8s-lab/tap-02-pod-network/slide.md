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

<br />
<br />

# Tập 2 - Pod Network
## Pause Container, veth pair & Network Namespace hoạt động ra sao

**Phần 0 — Nền tảng K8s Networking** · `#pause` `#veth` `#namespace` `#linux`
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## Mục tiêu tập này

- Giải thích vai trò của pause container trong mỗi Pod
- Vẽ được sơ đồ veth pair nối Pod vào Node bridge
- Dùng `nsenter` inspect network namespace của Pod từ Node
- Hiểu tại sao restart app container không mất network

**Prerequisites:** Cluster từ Tập 1 đang chạy với Flannel

---

## Pod là gì thực sự?

Hầu hết tutorial nói "Pod là container" — không đúng hoàn toàn.

**Pod = nhóm container chia sẻ cùng network namespace:**

```
┌─────────────────────────────────────────────────────┐
│                      POD                            │
│  ┌──────────────┐    ┌──────────────┐               │
│  │ pause/infra  │    │  app (nginx) │               │
│  │  container   │    │  container   │  Chia sẻ:     │
│  │              │    │              │  ─ eth0       │
│  │ Giữ ns sống  │    │ join ns của  │  ─ lo         │
│  │ khi app crash│    │    pause     │  ─ IP addr    │
│  └──────────────┘    └──────────────┘  ─ Port space │
│             Network Namespace                       │
└─────────────────────────────────────────────────────┘
```

**Tại sao cần pause container?**
- Network namespace tồn tại bao lâu? Chừng nào còn ít nhất 1 process giữ nó
- Nếu chỉ dùng app container: crash app → namespace mất → IP mất
- Pause container là "anchor" — crash app → pause vẫn sống → namespace còn nguyên

---

## veth pair: "Dây cáp ảo" giữa Pod và Node

```
  Pod namespace              Node namespace (root ns)
  ┌──────────────┐           ┌────────────────────────┐
  │    eth0      │           │    veth8a3f2b (no IP)  │
  │ 10.244.1.5   │◄─────────►│         │              │
  │  /24         │  virtual  │    cni0 bridge         │
  └──────────────┘  cable    │    10.244.1.1/24        │
                             │         │              │
                             │    eth0 (192.168.64.10)│
                             └────────────────────────┘
```

**Nguyên lý veth pair:**
- Tạo một lúc 2 interface: `vethXXXXX` ↔ `eth0`
- Mọi packet gửi vào một đầu → tự động ra đầu kia
- Một đầu trong Pod namespace, một đầu trong root namespace nối vào bridge

---

<!-- _class: lab -->

## 🔬 Lab Time: Khám phá Pod Network

Chúng ta sẽ thực hành các bước sau trong phần Lab:

1. **Khởi tạo Pod:** Tạo các Pod thử nghiệm trên các Worker Node khác nhau.
2. **Khám phá Pause Container:** Tìm PID của pause container và dùng `nsenter` để thâm nhập vào network namespace của Pod.
3. **Phân tích veth pair:** Quan sát "dây cáp ảo" nối giữa Pod và `cni0` bridge trên Node.
4. **Kiểm chứng tính bền vững:** Giả lập crash ứng dụng để chứng minh Pause container giữ cho IP của Pod không bị mất.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

| Khái niệm | Vai trò |
| :--- | :--- |
| **Pause container** | Anchor giữ network namespace sống khi app crash |
| **veth pair** | "Dây cáp ảo" — 1 đầu trong Pod ns, 1 đầu ở root ns |
| **cni0 bridge** | Switch ảo trên Node — kết nối tất cả Pods trên node |
| **`nsenter -n`** | Công cụ debug — vào ns Pod mà không cần `exec` |
| **Route `/16` trong Pod** | Anchor route CNI cài để bảo vệ traffic K8s khỏi bị default route đè |

**Lệnh debug hay dùng:**
```bash
# Từ Node: xem mạng bên trong Pod
nsenter -t <pause_pid> -n ip addr
nsenter -t <pause_pid> -n ss -tlnp

# Xem tất cả veth trên node
ip link show type veth

# Xem bridge ports
ip link show master cni0
```

> **Tập tiếp theo:** `cni0` bridge → iptables → kube-proxy. Packet đến Service VIP đi đường nào?
