# Lab 1.5: Cấu hình Ingress → Migrate sang Gateway API

## 🎯 Mục tiêu
- Deploy ứng dụng mẫu và routing bằng Ingress cũ.
- Xem file `nginx.conf` được sinh ra tự động.
- Migrate hoàn toàn sang Gateway API với HTTPRoute.

---

## 🗺️ Topology Diagram

**Ingress (Legacy) — L7 routing flow:**
```
External Client
    │  HTTP GET /api  Host: demo.lab.local
    ▼
NodePort :30XXX
    │
    ▼
ingress-nginx Pod  (nginx reverse proxy)
    │  đọc Ingress object → sinh nginx.conf tự động
    │  location /api  → proxy_pass app-v1:80
    │  location /admin → proxy_pass app-v2:80
    │
    ├─► /api   ──► Service app-v1 ──► Pod app-v1 (ClusterIP)
    └─► /admin ──► Service app-v2 ──► Pod app-v2 (ClusterIP)
```

**Gateway API (New) — Role-oriented flow:**
```
External Client
    │
    ▼
GatewayClass (cilium)  ← Infrastructure Provider định nghĩa implementation
    │
    ▼
Gateway: demo-gateway  ← Ops team: lắng nghe port 443, gắn TLS cert
    │  parentRefs ◄────────── HTTPRoute: api-route  ← Dev team: routing rules
    │
    ├─► path /api  ──► app-v1 (weight 90%) ┐  traffic splitting chuẩn
    │                  app-v2 (weight 10%) ┘  (Canary)
    │
    └─► path /admin ──► app-v2 (100%)
```

**So sánh phân quyền:**
```
Ingress (cũ)                     Gateway API (mới)
─────────────────────────────    ──────────────────────────────────
1 Ingress object                 GatewayClass  ← Infra Provider
  ↑ Ops chỉnh annotation         Gateway       ← Ops team
  ↑ Dev chỉnh routing            HTTPRoute     ← Dev team (độc lập)
  → conflict, annotation hell    → tách rõ trách nhiệm
```

---

## 🔬 Bước 1: Tạo ứng dụng mẫu (2 services)

```bash
# kubectl create deployment ... -- <args> đặt args vào trường command (override ENTRYPOINT)
# → runc cố chạy "--text=..." như binary → crash
# Dùng kubectl apply với args: field để truyền đúng vào ENTRYPOINT của /http-echo

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v1
spec:
  selector:
    matchLabels:
      app: app-v1
  template:
    metadata:
      labels:
        app: app-v1
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo
        args: ["-text=Hello from App v1"]
        ports:
        - containerPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-admin
spec:
  selector:
    matchLabels:
      app: app-admin
  template:
    metadata:
      labels:
        app: app-admin
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo
        args: ["-text=Hello from Admin"]
        ports:
        - containerPort: 5678
EOF

kubectl expose deployment app-v1 --port=5678 --name=app-v1-svc
kubectl expose deployment app-admin --port=5678 --name=app-admin-svc

# Verify
kubectl get pods
# app-v1-xxx    1/1  Running
# app-admin-xxx 1/1  Running
```

---

## 🔬 Bước 2: Cài ingress-nginx

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml

# Chờ controller ready
kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx
```

---

## 🔬 Bước 3: Tạo Ingress routing rule

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.local
      http:
        paths:
          - path: /app
            pathType: Prefix
            backend:
              service:
                name: app-v1-svc
                port:
                  number: 5678
          - path: /admin
            pathType: Prefix
            backend:
              service:
                name: app-admin-svc
                port:
                  number: 5678
EOF
```

---

## 🔬 Bước 4: Xem file nginx.conf được sinh ra

```bash
# Vào container nginx controller
kubectl exec -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o name) \
  -- cat /etc/nginx/nginx.conf | grep -A 20 "myapp.local"
```

**Quan sát:** Toàn bộ cấu hình Ingress được dịch thành cú pháp nginx config truyền thống. Mỗi lần bạn thêm/sửa Ingress object, file này được regenerate.

---

## 🔬 Bước 5: Test routing

```bash
INGRESS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

NODE_IP="192.168.56.11" <-- Đổi lại NODE IP của bạn

# Test /app
curl -H "Host: myapp.local" http://$NODE_IP:$INGRESS_PORT/app
# → Hello from App v1

# Test /admin
curl -H "Host: myapp.local" http://$NODE_IP:$INGRESS_PORT/admin
# → Hello from Admin
```

---

## 🔍 Phân tích Packet Walk: `/app` và `/admin`

### Hành trình đầy đủ từ `curl` đến backend Pod

```
curl -H "Host: myapp.local" http://192.168.56.11:30XXX/app
```

```
[1] Client → Node eth0 (192.168.56.11:30XXX)
        │
        │  iptables NodePort rule:
        │  KUBE-NODEPORTS: tcp dpt:30XXX → KUBE-SVC-ingress-nginx
        │  DNAT: :30XXX → 10.96.x.x:80  (ingress-nginx ClusterIP)
        ▼
[2] ingress-nginx Pod (10.244.x.x:80)
        │
        │  nginx đọc HTTP request:
        │    Host: myapp.local       ← khớp Ingress rule "host: myapp.local"
        │    GET /app                ← path matching
        │
        │  Routing decision (L7):
        │    path=/app  → backend: app-v1-svc:5678
        │    path=/admin → backend: app-admin-svc:5678
        │
        │  annotation rewrite-target: /
        │    → strip prefix: GET /app → GET /   (backend nhận "/" thay vì "/app")
        │
        │  nginx proxy_pass → DNS resolve app-v1-svc → CoreDNS → ClusterIP 10.96.y.y
        ▼
[3] iptables DNAT (trên Node đang chứa ingress-nginx Pod)
        │  DNAT: 10.96.y.y:5678 → 10.244.z.z:5678  (app-v1 Pod IP)
        ▼
[4] app-v1 Pod (10.244.z.z:5678)
        HTTP response: "Hello from App v1"
```

**Với `/admin` — routing decision khác nhau tại bước [2]:**

```
[2] nginx:
        GET /admin → backend: app-admin-svc:5678
        rewrite: GET /admin → GET /
        DNS resolve app-admin-svc → ClusterIP → DNAT → app-admin Pod
        HTTP response: "Hello from Admin"
```

### Điểm quan trọng cần nắm

| Bước | Cơ chế | Tầng |
| :--- | :--- | :--- |
| Client → nginx | NodePort DNAT (iptables KUBE-NODEPORTS) | L4 |
| nginx → backend | HTTP proxy_pass + path matching | **L7** |
| nginx → backend Pod | ClusterIP DNAT (iptables KUBE-SVC) | L4 |

> **2 lần DNAT:** Client→nginx (NodePort) và nginx→Pod (ClusterIP). nginx đứng giữa là L7 proxy — đây là điểm khác biệt căn bản so với kube-proxy thuần (chỉ có L4 DNAT, không đọc HTTP header).

> **rewrite-target: /** — nếu bỏ annotation này, backend sẽ nhận `GET /app` hoặc `GET /admin`. Với `http-echo` thì không quan trọng, nhưng với app thực tế thì path phải khớp với route bên trong app.

### Xác nhận bằng access log của nginx

```bash
# Xem nginx access log — mỗi request qua ingress đều được log
kubectl logs -n ingress-nginx \
  $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o name) \
  | tail -5

# Output mẫu:
# 192.168.56.1 - - [03/May/2026] "GET /app HTTP/1.1" 200 23 "-" "curl/8.x"
# upstream: "http://10.244.2.5:5678/"   ← Pod IP thật của app-v1
#                                 ↑ path "/" sau rewrite
```

---

## 🔬 Bước 6: Migrate sang Gateway API (Envoy Gateway)

Gateway API là **spec chuẩn K8s** (không phải implementation). Cần một data plane thực thi spec đó:

```
Gateway API Spec (K8s SIG Network)
    │
    ├── Envoy Gateway   ← Lab này dùng (CNCF project, self-contained)
    ├── Cilium          ← Sẽ thực hành trong Module 2
    ├── Traefik
    └── NGINX Gateway Fabric
```

```bash
# Dùng versioned tag — không dùng "latest" (không reproducible)
EG_VERSION="v1.3.0"
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/${EG_VERSION}/install.yaml

# Chờ Envoy Gateway control plane ready
kubectl rollout status deployment envoy-gateway -n envoy-gateway-system
# → deployment "envoy-gateway" successfully rolled out
```

```bash
# GatewayClass: Infra admin tạo 1 lần — chỉ định "dùng Envoy Gateway làm data plane"
# Tương tự IngressClass "nginx" nhưng role tách rõ hơn
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF

# Gateway: Ops team tạo — quy định port, protocol, TLS cert
# Envoy Gateway tự tạo 1 Envoy proxy pod cho mỗi Gateway object
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gw
  namespace: default
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      port: 80
      protocol: HTTP
EOF

# Verify Gateway và pods
kubectl get gateway prod-gw
# NAME      CLASS   ADDRESS   PROGRAMMED   AGE
# prod-gw   eg                False        70s
#                             ↑
#           Bare metal không có MetalLB → không có External IP
#           → Envoy Gateway set PROGRAMMED=False vì AddressNotAssigned
#           → ĐÂY LÀ BÌNH THƯỜNG — routing vẫn hoạt động!

# Xác nhận bằng kubectl describe: Listener-level condition = Programmed True
kubectl describe gateway prod-gw | grep -A 15 "Conditions:"
# Gateway-level: Accepted=True, AddressNotAssigned (lý do PROGRAMMED=False)
# Listener-level: Programmed=True ← data plane đã nhận config từ xDS server

# Envoy Gateway tạo 2 loại pod:
kubectl get pods -n envoy-gateway-system
# envoy-gateway-xxx              1/1 Running   ← control plane (watch K8s API, push xDS)
# envoy-default-prod-gw-xxx      2/2 Running   ← data plane proxy cho Gateway "prod-gw"
```

---

## 🔬 Bước 7: Tạo HTTPRoute (Dev team — không cần chỉnh Gateway)

```bash
# Dev team tạo HTTPRoute độc lập — không cần biết Gateway được implement thế nào
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
spec:
  parentRefs:
    - name: prod-gw       # ← gắn vào Gateway do Ops tạo
  hostnames: ["myapp.local"]
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /app
      backendRefs:
        - name: app-v1-svc
          port: 5678
    - matches:
        - path:
            type: PathPrefix
            value: /admin
      backendRefs:
        - name: app-admin-svc
          port: 5678
EOF

# Verify: HTTPRoute phải ở trạng thái Accepted
kubectl get httproute app-route
# NAME        HOSTNAMES          AGE
# app-route   ["myapp.local"]    10s

kubectl describe httproute app-route | grep -A5 "Conditions:"
# Type: Accepted    Status: True    ← phải True, không phải Unknown/False
# Type: ResolvedRefs Status: True   ← backend services tìm thấy
```

### Test routing trên bare metal (không có MetalLB)

```bash
# Bare metal: LoadBalancer service không có EXTERNAL-IP → dùng port-forward
kubectl get svc -n envoy-gateway-system
# NAME                            TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)
# envoy-default-prod-gw-<hash>    LoadBalancer   10.96.x.x     <pending>     80:3XXXX/TCP

# Port-forward vào Envoy proxy service
ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
  -o name | grep "envoy-default-prod-gw")

kubectl port-forward -n envoy-gateway-system ${ENVOY_SVC} 8080:80 &

# Test /app
curl -H "Host: myapp.local" http://localhost:8080/app
# → Hello from App v1

# Test /admin
curl -H "Host: myapp.local" http://localhost:8080/admin
# → Hello from Admin

# Dừng port-forward khi xong
kill $(lsof -ti :8080) 2>/dev/null || true
```

---

## 📊 So sánh: Ingress annotation vs HTTPRoute spec

```
Ingress (cũ)                            HTTPRoute (mới)
──────────────────────────────────      ────────────────────────────────────────
nginx.ingress.kubernetes.io/            spec.rules[].filters[]:
  rewrite-target: /                       - type: URLRewrite
↑ annotation không chuẩn, nginx-only      urlRewrite:
                                            path:
                                              type: ReplacePrefixMatch
                                              replacePrefixMatch: /
                                         ↑ field rõ ràng, portable across implementations

1 Ingress object (Dev + Ops trộn)       3 objects tách role rõ:
  annotations do Ops viết                 GatewayClass → Infra admin (1 lần)
  routing rules do Dev viết               Gateway      → Ops team
  → conflict khi scale team               HTTPRoute    → Dev team (độc lập)
```

---

## ✅ Câu hỏi kiểm tra

1. Trong file `nginx.conf`, upstream block được tạo ra dựa trên thông tin gì?
2. Sự khác biệt về phân quyền giữa Ingress và HTTPRoute là gì?
3. Thêm tính năng Traffic Splitting (90/10) vào HTTPRoute như thế nào?
4. Tại sao Gateway `ADDRESS = <pending>` trên bare metal nhưng routing vẫn hoạt động qua port-forward?

---

## 🧹 Dọn dẹp

```bash
# App resources
kubectl delete deployment app-v1 app-admin
kubectl delete svc app-v1-svc app-admin-svc

# Ingress resources
kubectl delete ingress my-ingress

# Gateway API resources
kubectl delete httproute app-route
kubectl delete gateway prod-gw
kubectl delete gatewayclass eg

# Envoy Gateway installation
kubectl delete namespace envoy-gateway-system

# Dừng port-forward nếu còn chạy
kill $(lsof -ti :8080) 2>/dev/null || true
```
