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

# 🔍 Tập 4: DNS trong Kubernetes & Thuế "ndots"
## Lý thuyết: CoreDNS, Headless Service & chi phí ẩn của ndots:5

**Network Thực Chiến** · Series: Kubernetes Networking · Tập 04


---

# Service Discovery: K8s dùng DNS

Thay vì hardcode ClusterIP (vì IP có thể thay đổi khi recreate Service), K8s cung cấp **DNS nội bộ**:

```bash
# Thay vì:
http://10.96.50.100:8080

# Bạn dùng:
http://my-service.my-namespace.svc.cluster.local:8080
# Hoặc ngắn gọn hơn (trong cùng namespace):
http://my-service:8080
```

**CoreDNS** là DNS server chính thức của K8s, chạy dưới dạng Deployment trong namespace `kube-system`.

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
# NAME                       READY   STATUS    NODE
# coredns-xxxxxxxxx-aaaaa    1/1     Running   controlplane
# coredns-xxxxxxxxx-bbbbb    1/1     Running   controlplane

# Xem Corefile — cấu hình CoreDNS
kubectl get cm coredns -n kube-system -o yaml
# → Thấy zone "cluster.local", forward "." đến upstream DNS (8.8.8.8 hoặc /etc/resolv.conf của Node)
```


---

# Cấu trúc tên miền nội bộ K8s

```
my-svc.my-namespace.svc.cluster.local
  │        │         │      │
  │        │         │      └── Domain của cluster
  │        │         └───────── Loại resource (svc)
  │        └─────────────────── Tên namespace
  └──────────────────────────── Tên Service
```

**CoreDNS** ánh xạ tên này thành **ClusterIP** của Service.

Với **Headless Service** (`clusterIP: None`), DNS trả về **danh sách IP Pod** trực tiếp — dùng cho StatefulSet và Service Discovery thủ công.


---

# Headless Service: DNS trả về Pod IP trực tiếp

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-db
spec:
  clusterIP: None   # ← Đây là Headless Service
  selector:
    app: postgres
  ports:
    - port: 5432
```

```bash
# DNS query cho Headless Service trả về nhiều A records:
nslookup my-db.default.svc.cluster.local
# Server: 10.96.0.10
# Address: 10.96.0.10:53
# Name: my-db.default.svc.cluster.local
# Address: 10.244.1.5   ← Pod A IP
# Address: 10.244.2.3   ← Pod B IP
```


---

# ⚠️ Thuế "ndots:5" - Chi phí ẩn của K8s DNS

Trong Pod, file `/etc/resolv.conf` mặc định có:
```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

`ndots:5` nghĩa là: **Nếu tên miền có ít hơn 5 dấu chấm**, trình phân giải sẽ thử **append search domain trước** khi query trực tiếp.


---

# Tại sao K8s chọn ndots:**5** cụ thể?

FQDN đầy đủ của một K8s Service có **4 dấu chấm**:

```
my-svc.default.svc.cluster.local
      ↑      ↑   ↑       ↑
      1      2   3       4 dấu chấm
```

`ndots:5` đảm bảo **mọi dạng tên ngắn** đều được thử qua search domain trước:

| Tên gọi | Số dấu chấm | < 5? | Hành vi |
| :--- | :---: | :---: | :--- |
| `my-svc` | 0 | ✅ | → thử search → `my-svc.default.svc.cluster.local` |
| `my-svc.default` | 1 | ✅ | → thử search → resolve đúng |
| `my-svc.default.svc` | 2 | ✅ | → thử search → resolve đúng |
| `my-svc.default.svc.cluster` | 3 | ✅ | → thử search → resolve đúng |
| `my-svc.default.svc.cluster.local` | 4 | ✅ | → thử search → resolve đúng |
| `api.github.com` | 2 | ✅ | → **thử search trước** → 3 NXDOMAIN thừa ⚠️ |

> Nếu dùng `ndots:4`, tên `my-svc.default.svc.cluster` (3 dấu chấm, < 4) vẫn OK — nhưng K8s chọn 5 để có buffer an toàn.


---

# Minh họa: Truy cập google.com từ trong Pod

```
curl https://google.com
        │
        ▼
1. google.com có < 5 dấu chấm → THỬ SEARCH DOMAIN TRƯỚC!
   └─ Query: google.com.default.svc.cluster.local  ❌ NXDOMAIN
   └─ Query: google.com.svc.cluster.local           ❌ NXDOMAIN
   └─ Query: google.com.cluster.local               ❌ NXDOMAIN
   └─ Query: google.com.                            ✅ Trả về 142.250.x.x
```

**Kết quả:** Truy cập 1 domain bên ngoài → mất **3 DNS queries thừa** (production với static IP). Môi trường DHCP (Vagrant, cloud VM) có thể nhiều hơn nếu Node thêm search domain từ DHCP — kiểm tra thực tế bằng `cat /etc/resolv.conf` trong Pod.

> Đây là lý do tại sao microservice nhiều network calls sẽ chịu ảnh hưởng đáng kể.


---

# Performance Impact: DNS Query Flood tại Scale

**Kịch bản thực tế:** Cluster 100 Pods, mỗi Pod gọi external API 10 lần/giây:

```
1 Pod × 1 call    =        4 DNS queries  (3 K8s search + 1 thật)
100 Pods × 10/s   =  4,000 queries/giây → CoreDNS
                                   ↑
                        3,000 queries THỪA mỗi giây
```

**Hậu quả dây chuyền:**

```
CoreDNS bị flood
    │
    ▼
UDP buffer đầy → packet drop
    │
    ▼
DNS timeout (5 giây mặc định)
    │
    ▼
HTTP request timeout → retry storm
    │
    ▼
Toàn bộ microservice bị ảnh hưởng
```

> **Incident thực tế:** Nhiều công ty gặp "mystery latency spike" khi scale lên. Root cause: CoreDNS overload do ndots:5 × số Pod tăng đột biến.


---

# Giải pháp — 3 Cấp độ Can thiệp

**🔵 Cấp độ Application** — Fix ngay, không cần thay đổi infra:
```bash
curl https://google.com.    ← Trailing dot = FQDN → query thẳng, bỏ qua search domain
```
> Tradeoff: Developer phải nhớ thêm `.` — dễ quên, khó enforce ở scale lớn.

**🟡 Cấp độ Infrastructure** — Fix trong Pod/Deployment YAML:
```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "1"   ← bare hostname (0 dấu chấm, 0 < 1) vẫn dùng search; còn lại query thẳng
```
> `ndots:1`: `google.com` (1 dấu chấm, không < 1) → query thẳng. `web-svc` (0 dấu chấm) → vẫn resolve qua search domain → K8s DNS hoạt động bình thường.
> Tradeoff: Cần update từng Deployment. Không giải quyết gốc rễ nếu có nhiều external calls.

**🟢 Cấp độ Architecture (Production)** — NodeLocal DNSCache:
```
Pod → 169.254.20.10 (cache local trên Node) → CoreDNS (chỉ khi cache miss)
```
> Tradeoff: Cần deploy DaemonSet, phức tạp hơn — nhưng giải quyết gốc rễ cho toàn cluster.


---

# 🚀 Autopath Plugin: Giải pháp Server-Side (Option 4)

**Ý tưởng:** Thay vì client gửi 4 queries riêng lẻ, CoreDNS tự thử search path **nội bộ** và trả về ngay:

```
Không có Autopath:                      Có Autopath:
                                        Pod → google.com.default.svc.cluster.local
Pod → google.com.default.svc...  ❌ ←────────────────────────────────────┐
Pod → google.com.svc.cluster...  ❌       CoreDNS nhận query, biết Pod    │
Pod → google.com.cluster.local   ❌       thuộc namespace nào → tự thử   │
Pod → google.com.                ✅       google.com. nội bộ → trả về ✅  │
                                                                           │
= 4 round-trips qua mạng              = 1 round-trip (CoreDNS làm hết) ──┘
```

Bật Autopath trong Corefile của CoreDNS:
```
.:53 {
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods verified
        autopath @kubernetes   # ← thêm dòng này
    }
    forward . /etc/resolv.conf
}
```

> **Tradeoff so sánh:**
> - Autopath = **server-side** fix — không cần thay đổi Pod/Deployment nào cả. CoreDNS tốn thêm CPU để lookup Pod → namespace → search path.
> - `ndots:1` = **client-side** fix — cần update từng Deployment YAML, nhưng giảm tải CoreDNS.
> - **NodeLocal DNSCache** = giảm latency + tải, nhưng không giảm số query thừa nếu không kết hợp Autopath hoặc ndots:1.


---

# NodeLocal DNSCache: Giải pháp chuẩn Production

```
Pod → 169.254.20.10 (Local cache trên Node) → Nếu miss → CoreDNS
```

- IP `169.254.20.10` là link-local address tĩnh, luôn có trên mọi Node khi cài NodeLocal DNSCache.
- **Giảm latency**: Cache nằm ngay trên Node, không cần network hop.
- **Giảm tải CoreDNS**: Các query lặp lại được trả lời từ cache.

```bash
# Cài đặt NodeLocal DNSCache (dùng versioned tag, không dùng master)
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')
kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
```


---

# Tổng kết Tập 4

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **CoreDNS** | DNS server nội bộ K8s, ánh xạ tên Service → ClusterIP |
| **Headless Service** | `clusterIP: None`, DNS trả về IP Pod trực tiếp |
| **ndots:5** | Gây ra 3 DNS query thừa khi truy cập domain ngoại |
| **Autopath plugin** | CoreDNS tự thử search path nội bộ → giảm 4 xuống 1 round-trip |
| **NodeLocal DNSCache** | Cache DNS tại Node IP `169.254.20.10`, giảm latency |


---

<!-- _class: title -->

# 👉 Chuyển sang Lab 1.4

Mở file **`lab-guide.md`** trong thư mục `1.4/` để thực hành:
- Bắt DNS query bằng `tcpdump` hoặc netshoot để thấy ndots:5 thực tế
- Triển khai NodeLocal DNSCache
- So sánh số lượng DNS query trước và sau khi cài
