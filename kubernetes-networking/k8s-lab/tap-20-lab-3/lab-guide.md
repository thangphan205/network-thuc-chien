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

Để bạn có thể chủ động thực hành, tìm hiểu và khắc phục sự cố trực tiếp, trước hết hãy dựng môi trường Lab ban đầu.

1. **SSH vào controlplane:**
   ```bash
   multipass shell controlplane
   ```

2. **Khởi tạo namespaces và triển khai các Pod:**
   ```bash
   # Tạo namespaces cho giám sát và sản xuất
   kubectl create namespace monitoring 2>/dev/null || true
   kubectl create namespace production 2>/dev/null || true

   # Gán nhãn cho namespace
   kubectl label namespace monitoring name=monitoring --overwrite

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

   # Triển khai Pod rogue ở namespace monitoring
   kubectl run rogue -n monitoring --image=nicolaka/netshoot -- sleep infinity
   ```

3. **Chờ các Pod sẵn sàng và lấy IP của Backend:**
   ```bash
   kubectl -n production wait --for=condition=Ready pod/backend --timeout=60s
   kubectl -n monitoring wait --for=condition=Ready pod/prometheus pod/rogue --timeout=60s
   
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   ```

4. **Áp dụng các chính sách NetworkPolicy ban đầu:**
   ```bash
   # Áp dụng chính sách default-deny
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

   # Áp dụng chính sách allow-prometheus-metrics
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

### Hiện tượng báo cáo từ vận hành & bảo mật
Bộ phận bảo mật và vận hành hệ thống phát hiện cảnh báo:
> "Hệ thống giám sát bảo mật ghi nhận có kết nối từ một IP lạ nằm trong namespace `monitoring` (được xác định là của Pod `rogue`) đi qua cổng `9090` của Backend trong namespace `production`. Theo thiết kế bảo mật, chỉ có duy nhất Pod `prometheus` mới được phép kết nối tới cổng này, các Pod khác phải bị chặn hoàn toàn."

### Nhiệm vụ của bạn
Bạn đóng vai trò là kỹ sư SRE/Infra, hãy tự thực hiện các bước sau để điều tra và khắc phục sự cố:

1. **Xác nhận hiện tượng (Tái hiện):**
   - Kiểm tra trạng thái các Pod (`kubectl get pods`).
   - Kiểm tra kết nối từ `prometheus` sang `backend:9090`.
   - Kiểm tra kết nối từ `rogue` sang `backend:9090`:
     ```bash
     kubectl -n monitoring exec rogue -- nc -zv -w 3 $BACKEND_IP 9090
     ```
2. **Điều tra nguyên nhân & Sửa lỗi:**
   - Kiểm tra trạng thái và thông tin chi tiết của các NetworkPolicy (`kubectl describe networkpolicy ...`).
   - Kiểm tra nhãn (Labels) của Namespace và các Pod.
   - Xác định tại sao lưu lượng truy cập từ các Pod lại không đi đúng theo thiết kế ban đầu.
   - Cập nhật lại cấu hình NetworkPolicy để đảm bảo chỉ cho phép Pod Prometheus được kết nối và chặn tất cả các Pod khác.
3. **Xác minh kết quả sửa lỗi:**
   - Kết nối từ Pod `prometheus` trong namespace `monitoring` tới `backend:9090` phải **thành công**.
   - Kết nối từ Pod `rogue` trong namespace `monitoring` tới `backend:9090` phải **bị chặn**.
   - Kết nối từ một Pod bất kỳ có nhãn `role: prometheus` ở namespace khác (ví dụ: `default`) tới `backend:9090` phải **bị chặn**.

---

## Bước 3: Lời giải & Phân tích chi tiết

> [!NOTE]
> Bạn chỉ nên xem phần này sau khi đã tự cố gắng tìm hiểu và khắc phục sự cố.

### Phân tích nguyên nhân (Root Cause Analysis)

Khi kiểm tra cấu hình NetworkPolicy `allow-prometheus-metrics` hiện tại, chúng ta phát hiện nguyên nhân lỗi logic nghiêm trọng:

#### 1. Lỗi Cú pháp YAML: Toán tử OR thay vì AND
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
  
  Do namespace `monitoring` đã được gán nhãn `name=monitoring`, nên đối tượng 1 khớp hoàn toàn. Điều này dẫn tới việc **mở toang cổng 9090 cho toàn bộ các Pod thuộc namespace `monitoring`** (bao gồm cả Pod `rogue`). Lỗi cú pháp này tạo ra lỗ hổng bảo mật nghiêm trọng.

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

---

### Các bước kiểm tra từng bước & Cách sửa lỗi

#### Bước 1: Kiểm tra cấu hình và nhãn hiện tại

Để điều tra nguyên nhân sự cố, bạn thực hiện chạy từng câu lệnh sau trên `controlplane`:

1. **Xem mô tả chi tiết của NetworkPolicy:**
   ```bash
   kubectl -n production describe networkpolicy allow-prometheus-metrics
   ```
   - **Mục đích:** Xem cách Kubernetes giải nghĩa và dịch chính sách bảo mật hiện tại.
   - **Điểm cần chú ý trong kết quả:**
     Quan sát phần `Spec.Ingress.From`, bạn sẽ thấy `NamespaceSelector` và `PodSelector` được liệt kê ở dạng **hai mục riêng biệt ngang hàng nhau** dưới `From` (thay vì lồng ghép vào nhau). Điều này chứng minh Kubernetes đang áp dụng quy tắc **OR (Hoặc)**.

2. **Xem cấu hình định dạng YAML của NetworkPolicy đang chạy:**
   ```bash
   kubectl -n production get networkpolicy allow-prometheus-metrics -o yaml
   ```
   - **Mục đích:** Xem file cấu trúc YAML nguyên bản trên Cluster để đối chiếu và phát hiện các dấu gạch ngang (`-`) thừa gây lỗi logic.
   - **Điểm cần chú ý trong kết quả:**
     Tại phần `ingress.from`, bạn sẽ thấy có 2 dấu `-` ở đầu dòng của cả `namespaceSelector` và `podSelector`. Mỗi dấu `-` đại diện cho một phần tử mảng độc lập, tương ứng với logic **OR**.

3. **Kiểm tra nhãn của Namespace giám sát:**
   ```bash
   kubectl get namespace monitoring --show-labels
   ```
   - **Mục đích:** Xác minh xem namespace `monitoring` có nhãn nào và có trùng khớp với cấu hình lỗi trong NetworkPolicy hay không.
   - **Điểm cần chú ý trong kết quả:**
     Bạn sẽ thấy nhãn `name=monitoring` xuất hiện trong cột `LABELS`. Do nhãn này tồn tại, quy tắc `NamespaceSelector` ở trên lập tức được kích hoạt, cho phép mọi Pod trong namespace này (bao gồm cả Pod `rogue`) gửi dữ liệu tới Backend.

4. **Kiểm tra nhãn của Pod Prometheus:**
   ```bash
   kubectl -n monitoring get pod prometheus --show-labels
   ```
   - **Mục đích:** Kiểm tra xem nhãn của Pod Prometheus có đúng là `role=prometheus` như quy hoạch thiết kế hay không.
   - **Điểm cần chú ý trong kết quả:**
     Pod Prometheus có nhãn `role=prometheus` hoàn toàn chính xác.

---

#### Bước 2: Sửa đổi và Áp dụng NetworkPolicy đúng

Sau khi đã xác định rõ nguyên nhân (do logic OR và nhãn namespace), hãy áp dụng giải pháp chính xác:

1. **Sửa đổi cú pháp YAML:**
   Chúng ta sẽ gộp bộ lọc Namespace và Pod thành điều kiện **AND** bằng cách loại bỏ dấu gạch ngang `-` dư thừa trước `podSelector`. Khi không có dấu `-`, `podSelector` sẽ trở thành thuộc tính con bổ trợ của `namespaceSelector`.
   
2. **Sử dụng nhãn mặc định an toàn hơn:**
   Thay vì lọc nhãn thủ công `name: monitoring`, ta sẽ chuyển sang dùng nhãn hệ thống mặc định được Kubernetes tự động gán từ phiên bản 1.21+: `kubernetes.io/metadata.name: monitoring`. Cách làm này giúp tránh được rủi ro quên gắn nhãn hoặc gán sai nhãn thủ công cho namespace.

Chạy lệnh sau để đè cấu hình đúng lên NetworkPolicy cũ:

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
