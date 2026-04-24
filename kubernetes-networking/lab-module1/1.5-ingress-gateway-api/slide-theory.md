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

# **Tập 5: Cuộc chuyển giao Ingress & Gateway API**
### Lý thuyết: ingress-nginx nghỉ hưu & kiến trúc Role-oriented của Gateway API v1.4

**Thang** | @NetworkThucChien

---

# Vấn đề: Làm sao traffic từ ngoài vào Pod?

Services kiểu `LoadBalancer` và `NodePort` hoạt động ở **Layer 4** (TCP/UDP):

```
Client → NodePort :30080 → Service → Pod
# Chỉ biết IP:Port, không biết gì về HTTP Host, Path, Header
```

Với ứng dụng Web hiện đại, bạn cần **Layer 7 routing**:
- `app.example.com/api` → Service A
- `app.example.com/admin` → Service B
- `beta.example.com` → Service C (Canary 10% traffic)

**Giải pháp:** Ingress (cũ) và Gateway API (mới).

---

# Ingress: Giải pháp cũ (Legacy)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /  # ← Config qua annotation!
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /api
            backend:
              service:
                name: api-service
                port:
                  number: 8080
```

**Vấn đề cốt lõi:** Tính năng nâng cao phải nhét vào **annotation** → không chuẩn hóa, mỗi controller (nginx, traefik, haproxy) dùng annotation khác nhau.

---

# ingress-nginx nghỉ hưu (2026)

Tháng 3/2026, project `kubernetes/ingress-nginx` chính thức **kết thúc vòng đời (EOL)**. Lý do:

1. **Mô hình phân quyền thiếu rõ ràng:** Dev và Ops đều phải chỉnh sửa cùng 1 Ingress object.
2. **Annotation hell:** Hàng trăm annotation không chuẩn hóa, vendor-lock-in.
3. **Không hỗ trợ traffic splitting chuẩn**: A/B testing, Canary phải dùng annotation hack.
4. **Gateway API đã GA** và giải quyết được tất cả vấn đề trên.

> Khuyến nghị: Bắt đầu migrate sang **Gateway API** ngay hôm nay.

---

# Gateway API: Kiến trúc Role-oriented

Gateway API phân chia trách nhiệm thành 3 tầng rõ ràng:

```
Infrastructure Provider (Cluster Admin)
    └── GatewayClass  ← "Nhà sản xuất bộ cân bằng tải"
         (Cilium GatewayClass, NGINX GatewayClass...)

Platform Team (Ops/Infra)
    └── Gateway  ← "Cổng vào cluster", cấu hình TLS, port
         (Lắng nghe port 443, gắn cert TLS)

Application Team (Dev)
    └── HTTPRoute  ← "Luật điều hướng traffic"
         (Path /api → Service A, Host beta → Service B)
```

---

# GatewayClass: Định nghĩa "Loại" Load Balancer

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
```

Tương tự như `StorageClass` cho PVC, `GatewayClass` định nghĩa **implementation** nào sẽ xử lý Gateway.

---

# Gateway: Cổng vào cluster (Ops quản lý)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gateway
  namespace: infra      # ← Ops team quản lý namespace này
spec:
  gatewayClassName: cilium
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        certificateRefs:
          - name: prod-tls-cert   # ← TLS cert do Ops quản lý
```

---

# HTTPRoute: Luật routing (Dev tự quản lý)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: my-app    # ← Dev team quản lý namespace này
spec:
  parentRefs:
    - name: prod-gateway
      namespace: infra
  hostnames: ["app.example.com"]
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-service
          port: 8080
          weight: 90    # ← Traffic splitting chuẩn!
        - name: api-canary
          port: 8080
          weight: 10
```

---

# So sánh: Ingress vs Gateway API

| Tiêu chí | Ingress | Gateway API |
| :--- | :--- | :--- |
| **Phân quyền** | Một object, ai cũng chỉnh | Tách rõ: Ops (Gateway) / Dev (HTTPRoute) |
| **Traffic splitting** | Annotation hack | Native `weight` field |
| **gRPC, TCPRoute** | Không hỗ trợ chuẩn | Hỗ trợ chuẩn |
| **Extensibility** | Annotation | Policy Attachment (chuẩn hóa) |
| **Trạng thái** | Legacy, EOL | GA từ K8s v1.28, v1.4 đang phát triển |

---

# Tổng kết Tập 5

| Khái niệm | Tóm tắt |
| :--- | :--- |
| **Ingress** | L7 routing cũ, annotation-based, EOL tháng 3/2026 |
| **GatewayClass** | Định nghĩa implementation (Cilium, NGINX...) |
| **Gateway** | Cổng vào cluster, do Ops quản lý, gắn TLS |
| **HTTPRoute** | Luật routing, do Dev quản lý, hỗ trợ traffic splitting |

---

# 👉 Chuyển sang Lab 1.5

Mở file **`lab-guide.md`** trong thư mục `1.5/` để thực hành:
- Cài ingress-nginx và cấu hình routing bằng Ingress cổ điển
- Xem file `nginx.conf` được tự động sinh ra
- Migrate sang Gateway API với Cilium làm controller
