---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', 'Noto Sans', sans-serif;
    font-size: 22px;
    background: #326ce5;
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
  .good { color: #86efac; font-weight: bold; }
  .bad  { color: #fca5a5; font-weight: bold; }
  .warn { color: #fcd34d; font-weight: bold; }
---
<!-- _class: title -->

# 🔌 Tập 2: CNI Specification
## Lý thuyết: Cơ chế ADD/DEL/GC/STATUS và cấu trúc `.conflist`

**Network Thực Chiến** · Series: Kubernetes Networking · Tập 02


---

# CNI là gì? Tại sao tồn tại?

**CNI** = **Container Network Interface** — một **đặc tả kỹ thuật** (specification) mở, không phải sản phẩm cụ thể.

Bài toán: Kubernetes cần giao tiếp với **nhiều hệ thống mạng khác nhau** (Flannel, Calico, Cilium, Weave...) mà không muốn viết code riêng cho từng hệ thống.

```
kubelet  ──── (gọi theo chuẩn CNI) ────►  CNI Plugin
              "Làm ơn cấp IP cho Pod này!"    (Flannel / Calico / Cilium...)
```

> CNI định nghĩa **giao diện giao tiếp** giữa Container Runtime (kubelet) và Network Plugin.


---

# CNI v1.1.0: Các động từ (Verbs)

CNI spec định nghĩa **5 động từ** chia thành 2 nhóm:

**3 verb cơ bản** (có từ đầu):

| Verb | Khi nào gọi | Mục đích |
| :--- | :--- | :--- |
| **ADD** | Khi tạo Pod | Cấp IP, tạo veth pair, cấu hình routing |
| **DEL** | Khi xóa Pod | Giải phóng IP, dọn dẹp veth, xóa routes |
| **CHECK** | kubelet sync | Xác minh cấu hình mạng Pod còn đúng không |

**2 verb mới trong v1.1.0** (giải quyết resource leak khi Node crash):

| Verb | Khi nào gọi | Mục đích |
| :--- | :--- | :--- |
| **GC** | Housekeeping | Dọn dẹp tài nguyên mạng của Pod đã mất |
| **STATUS** | Health check | Kiểm tra CNI plugin có sẵn sàng nhận lệnh không |


---

# Luồng ADD khi tạo Pod

```
kubectl apply -f pod.yaml
       │
       ▼
[1] API Server lưu Pod spec vào etcd
       │
       ▼
[2] Scheduler chọn Node → Ghi nodeSelector vào etcd
       │
       ▼
[3] kubelet trên Node đó nhận event
       │
       ▼
[4] kubelet tạo pause container (giữ network namespace)
       │
       ▼
[5] kubelet đọc /etc/cni/net.d/*.conflist
    → Xác định CNI plugin nào cần gọi
       │
       ▼
[6] kubelet EXEC binary CNI plugin với verb ADD
    Truyền vào: network namespace path, Pod name, container ID
       │
       ▼
[7] Plugin cấp IP, tạo veth, cấu hình iptables/eBPF
    Trả về: JSON chứa IP, routes, DNS info
       │
       ▼
[8] Pod sẵn sàng với IP! ✅
```


---

# Cấu trúc File `.conflist` — Chained Plugins

`/etc/cni/net.d/10-flannel.conflist` (ví dụ thực tế):

```json
{
  "cniVersion": "1.0.0",
  "name": "cbr0",
  "plugins": [
    {
      "type": "flannel",        ← Plugin chính: cấp IP, tạo veth
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true
      }
    },
    {
      "type": "portmap",        ← Plugin 2: xử lý hostPort mapping
      "capabilities": {
        "portMappings": true
      }
    },
    {
      "type": "bandwidth",      ← Plugin 3: giới hạn bandwidth (optional)
      "capabilities": {
        "bandwidth": true
      }
    }
  ]
}
```


---

# Chained Plugins: Tại sao lại chuỗi?

CNI cho phép **xếp chồng nhiều plugin** — kết quả của plugin trước là đầu vào của plugin sau:

```
kubelet gọi ADD
    │
    ▼
[Plugin 1: bridge]
  ✅ Tạo bridge mylab0
  ✅ Tạo veth pair
  ✅ Cấp IP qua host-local IPAM
  ✅ Thêm routes
    │ Kết quả (interface, IP) truyền xuống
    ▼
[Plugin 2: portmap]
  ✅ Tạo iptables rule cho hostPort mapping
    │
    ▼
[Plugin 3: firewall]
  ✅ Tạo iptables rule chặn spoofing IP
    │
    ▼
Trả về JSON kết quả tổng hợp cho kubelet
```


---

# IPAM: Quản lý địa chỉ IP

**IPAM** (IP Address Management) là sub-plugin chịu trách nhiệm **cấp và thu hồi IP**:

| IPAM Plugin | Cơ chế lưu trữ IP đã cấp | Phù hợp với |
| :--- | :--- | :--- |
| **host-local** | File trong `/var/lib/cni/networks/` | Dev/Lab (đơn giản, per-node) |
| **dhcp** | DHCP server truyền thống | Môi trường tích hợp datacenter |
| **calico-ipam** | etcd của Calico cluster | Production với Calico CNI |
| **whereabouts** | CRD trong K8s | Multus, multi-network |


---

# Verb GC: Giải pháp cho Resource Leak

**Vấn đề trước CNI v1.1.0:** Khi Node bị crash đột ngột:
- Pod bị terminate nhưng CNI không kịp gọi **DEL**
- Kết quả: IP bị giữ mãi trong `/var/lib/cni/networks/`, veth "zombie" còn tồn tại trên Node

**Giải pháp — Verb GC (v1.1.0):**

```bash
# kubelet định kỳ gọi GC với danh sách container ID còn sống
# Plugin so sánh với state file, xóa những thứ không còn cần
cnitool gc mylab-network \
  --valid-attachments='[{"containerID":"abc123"},{"containerID":"def456"}]'
```

> GC giống như "garbage collector" — dọn sạch tài nguyên mạng của Pod đã chết mà DEL chưa kịp chạy.


---

# Verb STATUS: Health Check

**STATUS** (mới từ v1.1.0) cho phép kubelet kiểm tra xem CNI plugin có **sẵn sàng** nhận lệnh không:

```bash
# Kubelet gọi STATUS trước khi schedule Pod lên Node
cnitool status mylab-network
# Exit code 0 = Plugin OK, sẵn sàng
# Exit code 1 = Plugin đang bị lỗi, KHÔNG schedule Pod lên Node này!
```

Trước đây, nếu CNI plugin bị lỗi (daemon crash, config sai), kubelet vẫn cố tạo Pod và thất bại ở bước ADD — mất thời gian và gây confusion. STATUS giải quyết điều này bằng cách **phát hiện sớm**.


---

# Biến môi trường khi kubelet gọi CNI

Kubelet truyền thông tin cho CNI plugin qua **biến môi trường**:

```bash
CNI_COMMAND=ADD          # Verb: ADD | DEL | CHECK | GC | STATUS
CNI_CONTAINERID=abc123   # ID của container (pause container)
CNI_NETNS=/proc/123/fd/4 # Path đến network namespace của container
CNI_IFNAME=eth0          # Tên interface sẽ tạo bên trong Pod
CNI_PATH=/opt/cni/bin    # Thư mục chứa CNI binary plugins
CNI_ARGS=K8S_POD_NAME=my-pod;K8S_POD_NAMESPACE=default
```

Plugin nhận config mạng qua **stdin** (JSON format từ file .conflist).


---

# Tổng kết Tập 2

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **CNI** | Đặc tả giao diện giữa kubelet và network plugin |
| **ADD/DEL** | Verb cơ bản: cấp IP khi tạo Pod, thu hồi khi xóa |
| **GC** | Dọn dẹp resource leak sau Node crash (mới v1.1.0) |
| **STATUS** | Health check plugin trước khi schedule Pod (mới v1.1.0) |
| **Chained plugins** | Nhiều plugin xếp chồng trong 1 `.conflist` |
| **IPAM** | Sub-plugin quản lý việc cấp/thu hồi IP |

> **Bài Lab 1.2:** Tự tay viết `.conflist` và gọi ADD/DEL bằng `cnitool` trực tiếp!


---

<!-- _class: title -->

# 👉 Chuyển sang Lab 1.2

Mở file **`lab-guide.md`** trong thư mục `1.2/` để thực hành:
- Cài CNI plugin binaries và `cnitool`
- Viết file `.conflist` với chained plugins (bridge + portmap)
- Gọi `cnitool add` thủ công và quan sát kết quả
- Gọi `cnitool del` và kiểm tra resource được giải phóng
