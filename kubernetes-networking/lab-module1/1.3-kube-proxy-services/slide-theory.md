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

# ⚙️ Tập 3: Kube-proxy & Bài toán Services
## Lý thuyết: EndpointSlice, iptables chains, IPVS & nftables mode

**Network Thực Chiến** · Series: Kubernetes Networking · Tập 03


---

# Services là gì? Bài toán cần giải

Pod có IP động — Pod chết đi, IP đó mất. Làm sao để client tìm được Pod?

```
Client → ??? → Pod A (10.244.1.5)  [đang chạy]
               Pod B (10.244.1.6)  [đang chạy]
               Pod C (10.244.2.3)  [vừa chết, IP mất]
```

**Service** cung cấp một IP ảo ổn định (**ClusterIP**) và tên DNS cố định, đứng trước các Pod:

```
Client → ClusterIP: 10.96.50.100 → kube-proxy → Pod A / Pod B
```


---

# Kube-proxy: Người dịch ClusterIP thành Pod IP

`kube-proxy` chạy trên **mọi Node**, theo dõi thay đổi từ API Server và lập trình các rule vào Linux kernel để thực hiện load balancing:

```
API Server
    │ Thông báo Service/EndpointSlice mới
    ▼
kube-proxy (trên mỗi Node)
    │ Lập trình rules vào:
    ├── iptables (mode mặc định cũ)
    ├── IPVS (mode hiệu năng cao)
    └── nftables (mode mới, GA từ K8s v1.33)
```


---

# EndpointSlice thay thế Endpoints (K8s v1.33)

`Endpoints` là tài nguyên cũ lưu danh sách IP của tất cả Pod sau Service. Vấn đề:

- Nếu Service có **1000 pods**, toàn bộ 1000 IP phải nằm trong **1 object** → Object khổng lồ, cập nhật chậm, tốn băng thông etcd.

**EndpointSlice** giải quyết bằng cách chia nhỏ:

```
Service: my-app
├── EndpointSlice-abc (max 100 pods/slice)
├── EndpointSlice-def (max 100 pods/slice)
└── EndpointSlice-xyz (max 100 pods/slice)
```

> Từ K8s v1.33, `Endpoints` API cũ bị **deprecated** hoàn toàn.


---

# iptables mode: Cơ chế DNAT

Khi bạn tạo Service `ClusterIP: 10.96.50.100`, kube-proxy tạo iptables rule:

```bash
# Chain KUBE-SERVICES là điểm vào
-A KUBE-SERVICES -d 10.96.50.100/32 -j KUBE-SVC-XXXXX

# Chain KUBE-SVC-XXXXX thực hiện load balancing bằng random module
-A KUBE-SVC-XXXXX -m statistic --mode random --probability 0.33 -j KUBE-SEP-AAAA
-A KUBE-SVC-XXXXX -m statistic --mode random --probability 0.5  -j KUBE-SEP-BBBB
-A KUBE-SVC-XXXXX -j KUBE-SEP-CCCC

# Chain KUBE-SEP-AAAA thực hiện DNAT đến Pod IP thực
-A KUBE-SEP-AAAA -j DNAT --to-destination 10.244.1.5:8080
```

> **Tại sao 0.33 → 0.5 → 1?** Đây là xác suất có điều kiện:
> Rule 1: 33% packet → Pod A. Rule 2: 50% của **phần còn lại** (67%) = 33% → Pod B. Rule 3: 100% còn lại = 33% → Pod C. Tổng mỗi Pod nhận đúng 1/3 tổng traffic.


---

# IPVS mode: Tại sao hiệu năng cao hơn?

iptables duyệt rules theo **danh sách tuần tự** → O(n) → Với 10,000 Services: cực chậm.

**IPVS** (IP Virtual Server) dùng **hash table** trong kernel → O(1):

```bash
# Xem bảng IPVS
ipvsadm -Ln

# Output:
# TCP  10.96.50.100:80 rr
#   -> 10.244.1.5:8080   Round-Robin
#   -> 10.244.1.6:8080   Round-Robin
#   -> 10.244.2.3:8080   Round-Robin
```

Thêm vào đó, IPVS hỗ trợ nhiều thuật toán LB hơn: `rr`, `lc`, `dh`, `sh`, `sed`, `nq`.

Kube-proxy tạo **interface `kube-ipvs0`** (dummy interface) và bind toàn bộ ClusterIP lên đó. `state DOWN` là bình thường — dummy interface không có physical link. Sự tồn tại của interface này là dấu hiệu IPVS mode đang chạy.


---

# externalTrafficPolicy: Ẩn mình quan trọng

| Policy | Luồng traffic NodePort | Đặc điểm |
| :--- | :--- | :--- |
| **Cluster** (default) | Đến bất kỳ Node nào → kube-proxy forward đến Pod bất kỳ | Phân phối đều, nhưng **mất source IP** (SNAT) |
| **Local** | Chỉ forward đến Pod **trên chính Node đó** | **Giữ source IP**, nhưng có thể mất cân bằng tải |

**Use case thực tế:** Khi bạn cần biết IP thực của client (WAF, Rate-limiting theo IP), hãy dùng `externalTrafficPolicy: Local`.


---

# nftables mode: Tương lai của kube-proxy

`nftables` là người kế nhiệm của `iptables` trong Linux kernel, GA trong K8s v1.33:

```bash
# Bật nftables mode trong kube-proxy ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
data:
  config.conf: |
    mode: nftables   # ← Thêm dòng này
```

**Ưu điểm:** Cú pháp rõ ràng hơn, atomic rule update (không bị race condition), hiệu năng tốt hơn với tập rule lớn.

```bash
# nftables rules do kube-proxy tạo (so sánh với iptables chain rời rạc)
sudo nft list table ip kube-proxy
# table ip kube-proxy {
#   set cluster-ips { ... }        ← Set chứa tất cả ClusterIP (thay vì n rules riêng lẻ)
#   chain prerouting { ... }
#   chain forward    { ... }
# }
# → Atomic update: toàn bộ table thay thế trong 1 transaction
```


---

# Tổng kết Tập 3

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **ClusterIP** | IP ảo ổn định đại diện cho nhóm Pod phía sau |
| **kube-proxy** | Lập trình iptables/IPVS/nftables để forward traffic đến Pod |
| **EndpointSlice** | Thay thế Endpoints, chia nhỏ danh sách Pod để scale tốt hơn |
| **IPVS vs iptables** | IPVS O(1) vs iptables O(n), phù hợp cluster lớn |
| **externalTrafficPolicy** | Local giữ source IP, Cluster phân tải đồng đều |


---

<!-- _class: title -->

# 👉 Chuyển sang Lab 1.3

Mở file **`lab-guide.md`** trong thư mục `1.3/` để thực hành:
- Tạo Deployment + Service và phân tích iptables chains
- Chuyển sang IPVS mode và dùng `ipvsadm`
- Thử nghiệm `externalTrafficPolicy`
