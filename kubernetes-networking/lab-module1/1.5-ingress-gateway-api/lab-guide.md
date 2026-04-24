# Lab 1.5: Cấu hình Ingress → Migrate sang Gateway API

## 🎯 Mục tiêu
- Deploy ứng dụng mẫu và routing bằng Ingress cũ.
- Xem file `nginx.conf` được sinh ra tự động.
- Migrate hoàn toàn sang Gateway API với HTTPRoute.

---

## 🔬 Bước 1: Tạo ứng dụng mẫu (2 services)

```bash
# App service
kubectl create deployment app-v1 --image=hashicorp/http-echo -- \
  --text="Hello from App v1"
kubectl expose deployment app-v1 --port=5678 --name=app-v1-svc

# Admin service
kubectl create deployment app-admin --image=hashicorp/http-echo -- \
  --text="Hello from Admin"
kubectl expose deployment app-admin --port=5678 --name=app-admin-svc
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

NODE_IP="192.168.56.11"

# Test /app
curl -H "Host: myapp.local" http://$NODE_IP:$INGRESS_PORT/app
# → Hello from App v1

# Test /admin
curl -H "Host: myapp.local" http://$NODE_IP:$INGRESS_PORT/admin
# → Hello from Admin
```

---

## 🔬 Bước 6: Migrate sang Gateway API (Cilium)

```bash
# Cài Cilium nếu chưa có (xem lab-module2)
# Hoặc dùng Envoy Gateway
kubectl apply -f https://github.com/envoyproxy/gateway/releases/latest/download/install.yaml

# Tạo GatewayClass
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF

# Tạo Gateway
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gw
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      port: 80
      protocol: HTTP
EOF
```

---

## 🔬 Bước 7: Tạo HTTPRoute (tương đương Ingress)

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
spec:
  parentRefs:
    - name: prod-gw
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
```

---

## ✅ Câu hỏi kiểm tra

1. Trong file `nginx.conf`, upstream block được tạo ra dựa trên thông tin gì?
2. Sự khác biệt về phân quyền giữa Ingress và HTTPRoute là gì?
3. Thêm tính năng Traffic Splitting (90/10) vào HTTPRoute như thế nào?

---

## 🧹 Dọn dẹp

```bash
kubectl delete deployment app-v1 app-admin
kubectl delete svc app-v1-svc app-admin-svc
kubectl delete ingress my-ingress
kubectl delete httproute app-route
```
