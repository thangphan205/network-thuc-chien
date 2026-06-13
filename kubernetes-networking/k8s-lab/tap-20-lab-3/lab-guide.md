# Lab Tập 20: Lab Thực Chiến 3 — Sự cố phân quyền truy cập chéo Namespace

---

## Mô hình hiện tại

Hệ thống gồm 2 namespace với các thành phần sau:

```
namespace: monitoring                    namespace: production
┌─────────────────────────────┐         ┌────────────────────────────────┐
│  Pod: prometheus            │         │  Pod: backend                  │
│  labels: role=prometheus    │──?──►   │  labels: app=backend           │
│                             │         │  port: 9090                    │
│  Pod: rogue                 │         │                                │
│  (không có label đặc biệt)  │         │  NetworkPolicy:                │
└─────────────────────────────┘         │    default-deny (all ingress)  │
                                        │    allow-prometheus-metrics    │
                                        └────────────────────────────────┘
```

**Mục tiêu thiết kế của policy `allow-prometheus-metrics`:**
- Chỉ cho phép Pod `prometheus` trong namespace `monitoring` kết nối tới `backend:9090`
- Tất cả các Pod khác (kể cả `rogue` trong cùng namespace) bị chặn

**Cấu hình NetworkPolicy đang áp dụng:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-metrics
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    - podSelector:
        matchLabels:
          role: prometheus
    ports:
    - protocol: TCP
      port: 9090
```

---

## Hiện tượng sự cố

Bộ phận vận hành báo cáo sự cố vào lúc 02:17 AM:

> "Prometheus không thu thập được metrics từ Backend. Dashboard Grafana trống. Logs Prometheus liên tục ghi `context deadline exceeded` khi scrape endpoint `http://<backend-ip>:9090/metrics`."

**Triệu chứng quan sát được:**

- Prometheus Pod trạng thái `Running`, không có lỗi khởi động
- Backend Pod trạng thái `Running`, không có lỗi khởi động
- Kết nối từ Prometheus sang Backend:9090 → **Connection Timeout**
- NetworkPolicy đã được đội infra thiết lập và xác nhận "đã apply thành công"
- Không có thay đổi hạ tầng nào được ghi nhận trong 24 giờ trước sự cố

---

## Tiến hành Troubleshoot

### Bước 0 — Dựng môi trường

SSH vào controlplane:

```bash
multipass shell controlplane
```

Tạo namespace và các thành phần:

```bash
kubectl create namespace monitoring 2>/dev/null || true
kubectl create namespace production 2>/dev/null || true
```

Triển khai Pod Backend (namespace `production`):

```bash
kubectl apply -n production -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels:
    app: backend
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["nc", "-lk", "-p", "9090"]
EOF
```

Triển khai Pod Prometheus (namespace `monitoring`):

```bash
kubectl apply -n monitoring -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: prometheus
  labels:
    role: prometheus
spec:
  containers:
  - name: p
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF
```

Triển khai Pod không liên quan (namespace `monitoring`):

```bash
kubectl run rogue -n monitoring --image=nicolaka/netshoot -- sleep infinity
```

Chờ tất cả Ready, lấy IP Backend:

```bash
kubectl -n production wait --for=condition=Ready pod/backend --timeout=60s
kubectl -n monitoring wait --for=condition=Ready pod/prometheus pod/rogue --timeout=60s
BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
echo "Backend IP: $BACKEND_IP"
```

Áp dụng NetworkPolicy:

```bash
kubectl apply -n production -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

kubectl apply -n production -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-metrics
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    - podSelector:
        matchLabels:
          role: prometheus
    ports:
    - protocol: TCP
      port: 9090
EOF
```

---

### Bước 1 — Tái hiện sự cố

Kiểm tra kết nối từ Prometheus sang Backend:

```bash
kubectl -n monitoring exec prometheus -- nc -zv -w 3 $BACKEND_IP 9090
```

Kiểm tra kết nối từ Pod `rogue` sang Backend:

```bash
kubectl -n monitoring exec rogue -- nc -zv -w 3 $BACKEND_IP 9090
```

Ghi lại kết quả cả 2 lệnh.

---

### Bước 2 — Kiểm tra trạng thái NetworkPolicy

Liệt kê các policy đang có trong namespace `production`:

```bash
kubectl -n production get networkpolicy
```

Xem chi tiết từng policy:

```bash
kubectl -n production describe networkpolicy default-deny
kubectl -n production describe networkpolicy allow-prometheus-metrics
```

---

### Bước 3 — Kiểm tra labels của Namespace và Pod

Kiểm tra labels của namespace `monitoring`:

```bash
kubectl get namespace monitoring --show-labels
```

Kiểm tra labels của Pod `prometheus`:

```bash
kubectl -n monitoring get pod prometheus --show-labels
```

Đối chiếu kết quả với selector trong policy `allow-prometheus-metrics`.

---

### Bước 4 — Đọc lại YAML policy

Xuất YAML đang áp dụng:

```bash
kubectl -n production get networkpolicy allow-prometheus-metrics -o yaml
```

Đọc kỹ phần `ingress.from`. Đếm số dấu `-` (gạch ngang) trong mảng `from`. Nghĩ về ý nghĩa của cấu trúc này.

---

### Bước 5 — Xác minh sau khi sửa (Test Matrix)

Sau khi tìm và sửa các lỗi, kiểm tra đầy đủ 3 trường hợp:

**Test 1:** Pod `prometheus` (đúng namespace, đúng label) → Backend:9090
```bash
kubectl -n monitoring exec prometheus -- nc -zv -w 3 $BACKEND_IP 9090
```

**Test 2:** Pod `rogue` (đúng namespace, sai label) → Backend:9090
```bash
kubectl -n monitoring exec rogue -- nc -zv -w 3 $BACKEND_IP 9090
```

**Test 3:** Pod có nhãn `role=prometheus` ở namespace `default` → Backend:9090
```bash
kubectl run fake-prom --image=nicolaka/netshoot --labels="role=prometheus" -- sleep infinity
kubectl wait --for=condition=Ready pod/fake-prom --timeout=30s
kubectl exec fake-prom -- nc -zv -w 3 $BACKEND_IP 9090
```

Kết quả đúng: Test 1 thành công, Test 2 và Test 3 bị chặn.

---

## Dọn dẹp

```bash
kubectl -n production delete networkpolicy default-deny allow-prometheus-metrics
kubectl -n production delete pod backend
kubectl -n monitoring delete pod prometheus rogue
kubectl delete pod fake-prom 2>/dev/null || true
```
