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

## Bước 1: Dựng môi trường Lab

Để bạn có thể chủ động thực hành, tìm hiểu và khắc phục sự cố trực tiếp, trước hết hãy dựng môi trường Lab chứa cấu hình lỗi.

1. **SSH vào controlplane:**
   ```bash
   multipass shell controlplane
   ```

2. **Khởi tạo namespaces và triển khai các Pod:**
   ```bash
   # Tạo namespaces cho giám sát và sản xuất
   kubectl create namespace monitoring 2>/dev/null || true
   kubectl create namespace production 2>/dev/null || true

   # Triển khai Pod Backend ở namespace production
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

   # Triển khai Pod Prometheus ở namespace monitoring
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

   # Triển khai Pod rogue (không có quyền thu thập metrics) ở namespace monitoring
   kubectl run rogue -n monitoring --image=nicolaka/netshoot -- sleep infinity
   ```

3. **Chờ các Pod sẵn sàng và lấy IP của Backend:**
   ```bash
   kubectl -n production wait --for=condition=Ready pod/backend --timeout=60s
   kubectl -n monitoring wait --for=condition=Ready pod/prometheus pod/rogue --timeout=60s
   
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   ```

4. **Áp dụng chính sách NetworkPolicy (Chứa cấu hình lỗi ban đầu):**
   ```bash
   # Chính sách chặn toàn bộ traffic ingress vào namespace production mặc định
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

   # Chính sách allow-prometheus-metrics (đang bị lỗi logic)
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

## Bước 2: Hiện tượng & Nhiệm vụ thực hành của bạn

### Hiện tượng báo cáo từ vận hành
Bộ phận vận hành báo cáo sự cố vào lúc 02:17 AM:
> "Prometheus không thu thập được metrics từ Backend. Dashboard Grafana trống. Logs Prometheus liên tục ghi `context deadline exceeded` khi scrape endpoint `http://<backend-ip>:9090/metrics`."

### Nhiệm vụ của bạn
Bạn đóng vai trò là kỹ sư SRE/Infra, hãy tự thực hiện các bước sau để tìm và sửa lỗi:

1. **Xác nhận hiện tượng lỗi:**
   - Kiểm tra trạng thái các Pod (`kubectl get pods`).
   - Kiểm tra log lỗi của Prometheus.
   - Thử kết nối từ `prometheus` sang `backend:9090` để chứng minh lỗi timeout kết nối:
     ```bash
     kubectl -n monitoring exec prometheus -- nc -zv -w 3 $BACKEND_IP 9090
     ```
2. **Tiến hành phân tích và sửa lỗi:**
   - Kiểm tra xem NetworkPolicy đang hoạt động như thế nào (`kubectl describe networkpolicy ...`).
   - Kiểm tra nhãn (Labels) của Namespace `monitoring` và Pod `prometheus`.
   - Tìm ra các điểm bất hợp lý trong cấu hình YAML hiện tại.
   - Viết lại cấu hình NetworkPolicy mới và áp dụng để sửa lỗi.
3. **Xác minh kết quả sửa lỗi:**
   - Kết nối từ Pod `prometheus` trong namespace `monitoring` tới `backend:9090` phải **thành công**.
   - Kết nối từ Pod `rogue` trong namespace `monitoring` tới `backend:9090` phải **bị chặn**.
   - Kết nối từ một Pod bất kỳ có nhãn `role: prometheus` ở namespace khác (ví dụ: `default`) tới `backend:9090` phải **bị chặn**.

---

## Bước 3: Lời giải & Phân tích chi tiết

> [!NOTE]
> Bạn chỉ nên xem phần này sau khi đã tự cố gắng tìm hiểu và khắc phục sự cố.

### Phân tích nguyên nhân (Root Cause Analysis)

Khi kiểm tra cấu hình NetworkPolicy `allow-prometheus-metrics` hiện tại, chúng ta phát hiện hai vấn đề cốt lõi:

#### 1. Lỗi Cú pháp YAML: Toán tử AND vs OR
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

#### 2. Vấn đề nhãn (Label) của Namespace
- Cấu hình ban đầu sử dụng `namespaceSelector.matchLabels.name: monitoring`.
- Tuy nhiên, khi khởi tạo namespace bằng lệnh `kubectl create namespace monitoring`, Kubernetes không tự động gán nhãn `name: monitoring`. Do đó, bộ lọc `namespaceSelector` sẽ không tìm thấy namespace nào thỏa mãn, dẫn đến việc chặn toàn bộ lưu lượng.
- **Giải pháp:**
  - *Cách 1 (Khuyên dùng):* Sử dụng nhãn hệ thống mặc định được Kubernetes tự động gán từ phiên bản 1.22+: `kubernetes.io/metadata.name: monitoring`.
  - *Cách 2:* Gán thủ công nhãn cho namespace `monitoring` bằng lệnh `kubectl label namespace monitoring name=monitoring`.

---

### Các bước kiểm tra từng bước & Cách sửa lỗi

#### Bước 1: Kiểm tra nhãn (Labels) của Namespace và Pod
Để xác định xem các bộ lọc trong NetworkPolicy có khớp với thực tế hay không:
```bash
# Kiểm tra nhãn của namespace monitoring
kubectl get namespace monitoring --show-labels

# Kiểm tra nhãn của Pod prometheus
kubectl -n monitoring get pod prometheus --show-labels
```
*Kết quả quan sát:* Namespace `monitoring` không hề có nhãn `name: monitoring` (Chỉ có nhãn hệ thống mặc định `kubernetes.io/metadata.name: monitoring`). Do đó bộ lọc namespace ban đầu không hoạt động.

#### Bước 2: Sửa đổi và Áp dụng NetworkPolicy đúng
Chúng ta gộp bộ lọc Namespace và Pod thành điều kiện **AND** bằng cách loại bỏ dấu gạch ngang `-` dư thừa trước `podSelector`, đồng thời chuyển sang dùng nhãn hệ thống mặc định của namespace:

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

## Bước 4: Xác minh kết quả (Test Matrix)

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

Kết quả đúng: Test Case 1 kết nối thành công, Test Case 2 và Test Case 3 bị chặn.

---

## Dọn dẹp

Sau khi hoàn thành bài lab, tiến hành dọn dẹp các tài nguyên để trả lại môi trường sạch:

```bash
kubectl -n production delete networkpolicy default-deny allow-prometheus-metrics
kubectl -n production delete pod backend
kubectl -n monitoring delete pod prometheus rogue
kubectl delete pod fake-prom 2>/dev/null || true
```
