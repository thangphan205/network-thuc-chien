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

---

## Hiện tượng sự cố

Bộ phận vận hành báo cáo sự cố vào lúc 02:17 AM:

> "Prometheus không thu thập được metrics từ Backend. Dashboard Grafana trống. Logs Prometheus liên tục ghi `context deadline exceeded` khi scrape endpoint `http://<backend-ip>:9090/metrics`."

### Các bước kiểm tra hiện tượng

Trước khi tiến hành phân tích sâu, ta cần thu thập thông tin và kiểm tra thực tế hiện tượng lỗi để có cái nhìn chính xác nhất:

1. **Kiểm tra trạng thái hoạt động của các Pod:**
   Đảm bảo rằng các Pod liên quan đều đang ở trạng thái `Running` và không gặp lỗi restart liên tục.
   ```bash
   kubectl get pods -n monitoring
   kubectl get pods -n production
   ```
2. **Kiểm tra logs của Prometheus:**
   Tìm kiếm các lỗi liên quan đến kết nối hoặc timeout khi scrape metrics từ Backend.
   ```bash
   kubectl logs -n monitoring -l role=prometheus --tail=50
   ```
3. **Kiểm tra kết nối trực tiếp (Replicate/Confirm):**
   Thử kết nối thủ công bằng Netcat (`nc`) từ bên trong Pod Prometheus sang Backend IP ở cổng `9090` để xác nhận việc kết nối bị chặn (Timeout).
   ```bash
   kubectl -n monitoring exec prometheus -- nc -zv -w 3 $BACKEND_IP 9090
   ```

---

## Phân tích nguyên nhân (Root Cause Analysis)

Khi xem xét cấu hình NetworkPolicy `allow-prometheus-metrics` hiện tại, chúng ta phát hiện hai vấn đề cốt lõi dẫn đến sự cố kết nối:

### 1. Phân tích Cú pháp YAML: Toán tử AND vs OR trong NetworkPolicy
Trong Kubernetes NetworkPolicy, cấu trúc của trường `ingress.from` quyết định cách kết hợp các bộ lọc (selectors):
- **Toán tử OR (Hoặc) - Cấu hình lỗi hiện tại:**
  ```yaml
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    - podSelector:
        matchLabels:
          role: prometheus
  ```
  Do có hai dấu gạch ngang `-` độc lập dưới `from`, Kubernetes hiểu đây là một mảng gồm hai đối tượng lọc riêng biệt:
  - *Đối tượng 1:* Cho phép kết nối từ **tất cả** các Pod thuộc bất kỳ namespace nào có nhãn `name: monitoring`.
  - *Đối tượng 2:* Cho phép kết nối từ các Pod có nhãn `role: prometheus` **nhưng chỉ trong cùng namespace** với NetworkPolicy (`production`).
  
  Do đó, cấu hình này vô tình chặn kết nối từ Pod `prometheus` ở namespace `monitoring` (vì nó không nằm trong namespace `production` để khớp với đối tượng 2, và đối tượng 1 cũng không khớp do vấn đề nhãn namespace bên dưới). Đồng thời, nếu namespace khớp, nó sẽ cho phép cả Pod `rogue` (không đúng mục tiêu bảo mật).

- **Toán tử AND (Và) - Cấu hình đúng mong muốn:**
  ```yaml
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          role: prometheus
  ```
  Bằng cách bỏ dấu gạch ngang `-` trước `podSelector`, ta gộp chúng thành các trường của cùng một đối tượng lọc. Kubernetes sẽ chỉ cho phép các Pod thỏa mãn đồng thời cả hai điều kiện: có nhãn `role: prometheus` **VÀ** nằm trong namespace có nhãn khớp.

### 2. Vấn đề nhãn (Label) của Namespace
- Cấu hình ban đầu sử dụng `namespaceSelector.matchLabels.name: monitoring`.
- Tuy nhiên, khi khởi tạo namespace bằng lệnh `kubectl create namespace monitoring`, Kubernetes không tự động gán nhãn `name: monitoring`. Do đó, bộ lọc `namespaceSelector` sẽ không tìm thấy namespace nào thỏa mãn, dẫn đến việc chặn toàn bộ lưu lượng.
- **Giải pháp:**
  - *Cách 1 (Khuyên dùng):* Sử dụng nhãn hệ thống mặc định được Kubernetes tự động gán từ phiên bản 1.22+: `kubernetes.io/metadata.name: monitoring`.
  - *Cách 2:* Gán thủ công nhãn cho namespace `monitoring` bằng lệnh `kubectl label namespace monitoring name=monitoring`.

---

## Tiến hành Troubleshoot từng bước

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

Áp dụng NetworkPolicy (Chứa lỗi ban đầu):

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

### Bước 1 — Kiểm tra hiện tượng & Tái hiện sự cố

1. **Kiểm tra kết nối từ Prometheus sang Backend:**
   ```bash
   kubectl -n monitoring exec prometheus -- nc -zv -w 3 $BACKEND_IP 9090
   ```
   *Kết quả mong đợi:* Gặp lỗi **Connection timeout** (không thể kết nối).

2. **Kiểm tra kết nối từ Pod `rogue` sang Backend:**
   ```bash
   kubectl -n monitoring exec rogue -- nc -zv -w 3 $BACKEND_IP 9090
   ```
   *Kết quả mong đợi:* Cũng bị chặn (Connection timeout).

---

### Bước 2 — Kiểm tra trạng thái NetworkPolicy hiện tại

Xem danh sách NetworkPolicy đang hoạt động trong namespace `production`:

```bash
kubectl -n production get networkpolicy
```

Xem cấu hình chi tiết của policy `allow-prometheus-metrics` để phân tích:

```bash
kubectl -n production describe networkpolicy allow-prometheus-metrics
```
*Hãy chú ý phần `Spec.Ingress.From`:* Xem Kubernetes đang phân tách các bộ lọc này thành các quy tắc riêng biệt như thế nào.

---

### Bước 3 — Kiểm tra Nhãn (Labels) của Namespace và Pod

Để xác định xem các bộ lọc trong NetworkPolicy có khớp với thực tế hay không, ta thực hiện kiểm tra nhãn:

1. **Kiểm tra nhãn của namespace `monitoring`:**
   ```bash
   kubectl get namespace monitoring --show-labels
   ```
   *Quan sát:* Namespace `monitoring` có nhãn `name: monitoring` hay không? Thông thường, kết quả sẽ không có nhãn này, dẫn tới việc `namespaceSelector` trong policy bị vô hiệu hóa.

2. **Kiểm tra nhãn của Pod `prometheus`:**
   ```bash
   kubectl -n monitoring get pod prometheus --show-labels
   ```
   *Quan sát:* Pod có nhãn `role: prometheus` chính xác như thiết kế chưa? (Nhãn này đã đúng).

---

### Bước 4 — Sửa đổi và Áp dụng Cấu hình đúng

Chúng ta sẽ sửa NetworkPolicy để gộp bộ lọc Namespace và Pod thành điều kiện **AND**, đồng thời sử dụng nhãn hệ thống mặc định của namespace (`kubernetes.io/metadata.name: monitoring`):

```bash
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
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          role: prometheus
    ports:
    - protocol: TCP
      port: 9090
EOF
```

---

### Bước 5 — Xác minh sau khi sửa (Test Matrix)

Sau khi áp dụng cấu hình đúng, thực hiện kiểm tra kỹ lưỡng ma trận kết nối để đảm bảo không bị lỗi chéo hoặc lọt cấu hình bảo mật:

* **Test Case 1: Đúng Namespace, Đúng Pod Label (Prometheus)** -> Kỳ vọng: **Thành công**
  ```bash
  kubectl -n monitoring exec prometheus -- nc -zv -w 3 $BACKEND_IP 9090
  ```

* **Test Case 2: Đúng Namespace, Sai Pod Label (Rogue)** -> Kỳ vọng: **Bị chặn (Timeout)**
  ```bash
  kubectl -n monitoring exec rogue -- nc -zv -w 3 $BACKEND_IP 9090
  ```

* **Test Case 3: Sai Namespace, Đúng Pod Label (Fake Prometheus ở namespace default)** -> Kỳ vọng: **Bị chặn (Timeout)**
  ```bash
  kubectl run fake-prom --image=nicolaka/netshoot --labels="role=prometheus" -- sleep infinity
  kubectl wait --for=condition=Ready pod/fake-prom --timeout=30s
  kubectl exec fake-prom -- nc -zv -w 3 $BACKEND_IP 9090
  ```

Kết quả đúng: Test Case 1 thành công, Test Case 2 và Test Case 3 bị chặn.

---

## Dọn dẹp

```bash
kubectl -n production delete networkpolicy default-deny allow-prometheus-metrics
kubectl -n production delete pod backend
kubectl -n monitoring delete pod prometheus rogue
kubectl delete pod fake-prom 2>/dev/null || true
```
