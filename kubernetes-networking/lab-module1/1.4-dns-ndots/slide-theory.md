---
marp: true
theme: gaia
paginate: true
backgroundColor: #0f172a
color: #e2e8f0
---

<style>
h1 { color: #38bdf8; font-size: 1.5em; }
h2 { color: #7dd3fc; }
strong { color: #fbbf24; }
code { background: #1e293b; color: #86efac; padding: 2px 6px; border-radius: 4px; }
blockquote { border-left: 4px solid #38bdf8; color: #94a3b8; padding-left: 1em; }
table { font-size: 0.78em; }
th { background: #1e40af; color: white; }
td { background: #1e293b; }
pre { background: #1e293b; font-size: 0.72em; }
</style>

# **Tập 4: DNS trong Kubernetes & Thuế "ndots"**
### Lý thuyết: CoreDNS, Headless Service & chi phí ẩn của ndots:5

**Thang** | @NetworkThucChien

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

**Kết quả:** Truy cập 1 domain bên ngoài → mất **4 DNS queries thừa** trước khi ra được Internet!

> Đây là lý do tại sao microservice nhiều network calls sẽ chịu ảnh hưởng đáng kể.

---

# Giải pháp cho thuế ndots

**Option 1:** Luôn thêm dấu `.` cuối tên miền ngoại (Fully Qualified):
```
curl https://google.com.    ← Dấu chấm cuối = FQDN → Query thẳng, không search
```

**Option 2:** Giảm `ndots` trong Pod spec:
```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "2"   ← Chỉ thêm search domain nếu < 2 dấu chấm
```

**Option 3 (tốt nhất):** Triển khai **NodeLocal DNSCache** để cache tại local, giảm round-trip đến CoreDNS.

---

# NodeLocal DNSCache: Giải pháp chuẩn Production

```
Pod → 169.254.20.10 (Local cache trên Node) → Nếu miss → CoreDNS
```

- IP `169.254.20.10` là link-local address tĩnh, luôn có trên mọi Node khi cài NodeLocal DNSCache.
- **Giảm latency**: Cache nằm ngay trên Node, không cần network hop.
- **Giảm tải CoreDNS**: Các query lặp lại được trả lời từ cache.

```bash
# Cài đặt NodeLocal DNSCache
kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
```

---

# Tổng kết Tập 4

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **CoreDNS** | DNS server nội bộ K8s, ánh xạ tên Service → ClusterIP |
| **Headless Service** | `clusterIP: None`, DNS trả về IP Pod trực tiếp |
| **ndots:5** | Gây ra 3 DNS query thừa khi truy cập domain ngoại |
| **NodeLocal DNSCache** | Cache DNS tại Node IP `169.254.20.10`, giảm latency |

---

# 👉 Chuyển sang Lab 1.4

Mở file **`lab-guide.md`** trong thư mục `1.4/` để thực hành:
- Bắt DNS query bằng `tcpdump` hoặc netshoot để thấy ndots:5 thực tế
- Triển khai NodeLocal DNSCache
- So sánh số lượng DNS query trước và sau khi cài
