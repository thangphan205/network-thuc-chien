# Study Guide — Tập 15: Union Logic và NetworkPolicy như Security Group

> **Mục tiêu:** Sau khi đọc và thực hành tài liệu này, học viên hiểu rõ tại sao K8s NetworkPolicy chỉ là allowlist thuần túy, cơ chế cộng hưởng (union) giữa nhiều policies, và cách dùng Calico GlobalNetworkPolicy để thực hiện Explicit Deny.

---

## 1. Đặt vấn đề

### Câu hỏi thực tế

Bạn đang vận hành hệ thống trong namespace `production`. Có 3 yêu cầu đến cùng lúc:

- **Dev team:** "Cho phép `frontend` truy cập `backend` port 8080."
- **Data team:** "Cho phép `frontend2` truy cập `backend` port 8080."
- **CISO:** "Sau khi cấp quyền xong, tôi muốn **chặn riêng** `frontend2` vì phát hiện bất thường."

Nếu bạn nghĩ K8s NetworkPolicy hoạt động như một tường lửa truyền thống (có thứ tự rule, có DENY tường minh), bạn sẽ thiết kế sai — và đó là lỗ hổng bảo mật logic nghiêm trọng.

Tập này giải quyết câu hỏi đó từ gốc rễ.

---

## 2. Nền tảng lý thuyết

### 2.1 NetworkPolicy là Allowlist — không phải Firewall ACL

K8s NetworkPolicy theo mô hình **allowlist** (chỉ cho phép):
- Không có NetworkPolicy nào → Pod nhận tất cả traffic (default allow).
- Có ít nhất một NetworkPolicy select Pod → Pod chỉ nhận traffic khớp với ít nhất một rule trong các policy đó.
- Không có rule nào khớp → traffic bị từ chối (implicit deny).

**Điều quan trọng:** Không có trường `action` trong K8s NetworkPolicy spec. Mọi rule đều là `allow`.

```yaml
# K8s NetworkPolicy spec — chỉ có "allow", không có "deny"
ingress:
- from:
  - podSelector:
      matchLabels:
        app: frontend
  ports:
  - protocol: TCP
    port: 8080
# Dịch nghĩa: "Cho phép ingress từ pod có label app=frontend vào port 8080"
# Không có cách nào viết "Từ chối ingress từ..."
```

### 2.2 Union Logic — tất cả policies là OR với nhau

Khi nhiều NetworkPolicy cùng select một Pod, kết quả là **phép hợp (union)** của tất cả ingress/egress rules:

```
Policy A: allow from frontend   → port 8080
Policy B: allow from frontend2  → port 8080

Kết quả cuối cùng cho backend Pod:
  Ingress ALLOWED nếu: (from frontend AND port 8080) OR (from frontend2 AND port 8080)
```

Không có khái niệm "policy sau ghi đè policy trước". Không có priority. Mỗi policy chỉ có thể mở thêm cổng, không bao giờ đóng cổng mà policy khác đã mở.

### 2.3 So sánh với AWS Security Group và NACL

| Đặc điểm | K8s NetworkPolicy | AWS Security Group | AWS NACL |
|---|---|---|---|
| Mô hình | Allowlist | Allowlist | Allow + Deny |
| Nhiều rules | Cộng hưởng (union) | Cộng hưởng (union) | Có thứ tự (priority) |
| DENY tường minh | Không có | Không có | Có (Rule 100 Deny...) |
| Conflict giữa rules | Không xảy ra | Không xảy ra | Rule số thấp thắng |
| Ghi đè | Không thể | Không thể | Có thể |

**K8s NetworkPolicy = AWS Security Group. Không phải NACL.**

Ví dụ AWS Security Group:
```
SG-web:  Allow port 80 from 0.0.0.0/0
SG-ssh:  Allow port 22 from 10.0.0.5/32
SG-app:  Allow port 8080 from 10.0.1.0/24

→ EC2 instance nhận port 80, 22, 8080
→ SG-web không thể "cancel" SG-ssh
→ Không có thứ tự, không có conflict
```

Chính xác đây là cách K8s NetworkPolicy hoạt động.

### 2.4 Tại sao thiết kế như vậy?

Lý do thiết kế union logic:
- **Decoupling:** Mỗi team có thể tự quản lý NetworkPolicy của mình mà không ảnh hưởng đến team khác.
- **Tránh race condition:** Nếu có priority, việc 2 operator cùng apply policy sẽ tạo ra kết quả không xác định.
- **Đơn giản hóa:** 99% use case chỉ cần "mở thêm cổng cho service X" — union logic đáp ứng trực tiếp.

Hệ quả: Để "deny" một traffic cụ thể, cách duy nhất trong K8s NetworkPolicy chuẩn là **không viết rule allow cho traffic đó**. Bạn không thể deny một traffic mà đã có rule allow trong một policy khác.

### 2.5 Giải pháp khi cần Explicit Deny — Calico GlobalNetworkPolicy

Calico mở rộng K8s NetworkPolicy với:

| Tính năng | K8s NetworkPolicy | Calico GlobalNetworkPolicy |
|---|---|---|
| Scope | Namespace | Cluster-wide |
| `action` | (không có, implicit allow) | `Allow`, `Deny`, `Pass` |
| `order` | (không có) | Số thực, số nhỏ = ưu tiên cao |
| Selector syntax | `matchLabels` | CEL-like: `app == 'backend'` |

Calico ánh xạ K8s NetworkPolicy sang internal policy với **order mặc định là 1000**. Khi bạn tạo `GlobalNetworkPolicy` với `order: 100`, nó được đánh giá **trước** K8s NetworkPolicy:

```
Luồng đánh giá của Calico (thứ tự order tăng dần):

order: 100  → GlobalNetworkPolicy deny-frontend2-explicit
               action: Deny từ frontend2  ← Gói tin từ frontend2 dừng ở đây
               
order: 1000 → K8s NetworkPolicy allow-frontend2
               action: Allow từ frontend2  ← Không bao giờ đến đây vì đã bị Deny ở trên
               
order: 1000 → K8s NetworkPolicy allow-frontend
               action: Allow từ frontend   ← frontend đi qua bình thường
```

### 2.6 Cách phân biệt nhanh Rule Allow và Deny trong NetworkPolicy

Để làm chủ việc thiết kế và giám sát hệ thống bảo mật, kỹ sư DevOps bắt buộc phải phân biệt được chính xác một rule trong policy đang hoạt động ở chế độ **Allow (Cho phép)** hay **Deny (Chặn)**.

#### 🟢 Nhận diện luật ALLOW:
*   **Kubernetes NetworkPolicy chuẩn:**
    *   Tất cả các định nghĩa dưới trường `ingress:` (luồng vào) hoặc `egress:` (luồng ra) đều mặc định là luật **Allow** (Allowlist thuần túy). 
    *   Không hề tồn tại bất cứ từ khóa hay thuộc tính `action` nào. Mọi dòng cấu hình IP, Namespace Selector hay Pod Selector đều mang ý nghĩa: *"Cho phép traffic đi qua"*.
*   **Calico GlobalNetworkPolicy / NetworkPolicy mở rộng:**
    *   Nhận diện trực tiếp qua khai báo trường **`action: Allow`** bên trong các quy tắc của `ingress` hoặc `egress`.

#### 🔴 Nhận diện luật DENY:
*   **Kubernetes NetworkPolicy chuẩn:**
    *   **Không thể viết luật Deny tường minh (Explicit Deny).**
    *   Luật Deny chỉ tồn tại ở dạng **Ngầm định (Implicit Deny / Default Deny)**: Khi một Pod bị chọn bởi `podSelector` của bất kỳ policy nào, nó sẽ tự động bị "cô lập" và chặn toàn bộ các traffic khác ngoài các luồng được allowlist cho phép.
*   **Calico GlobalNetworkPolicy / NetworkPolicy mở rộng:**
    *   Nhận diện trực tiếp qua khai báo trường **`action: Deny`** dưới mỗi rule. Lúc này gói tin khớp điều kiện sẽ bị Drop chủ động ngay lập tức.
*   **Kubernetes AdminNetworkPolicy (K8s 1.29+):**
    *   Nhận diện thông qua thuộc tính **`action: Deny`** ở tầng Cluster-scoped.

---

## 3. Mô hình mục tiêu của Lab

Sau khi hoàn thành tất cả thực nghiệm, trạng thái cuối cùng là:

```
Namespace: production
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  [frontend]  ──────────────────────────► [backend:8080] │
│  app=frontend   Policy A (order:1000)      app=backend  │
│                                                         │
│  [frontend2] ──── DENY (order:100) ──── X [backend:8080]│
│  app=frontend2   Calico GNP chặn trước                  │
│                                                         │
│  [db-pod]    ──── không có rule ────── X [backend:8080] │
│  app=database    implicit deny                          │
│                                                         │
└─────────────────────────────────────────────────────────┘

Policies đang active:
  - default-deny          (K8s, podSelector: {}, block all ingress)
  - allow-frontend        (K8s, Policy A, order: 1000)
  - allow-frontend2       (K8s, Policy B, order: 1000) ← bị Calico GNP chặn trước
  - deny-frontend2-explicit (Calico GNP, order: 100)
```

---

## 4. Lab — Thực hành từng bước

### 4.1 Môi trường

**Yêu cầu:**
- Cụm K8s với Calico CNI (từ Tập 9)
- Namespace `production` (sẽ tạo lại nếu chưa có)

**SSH vào controlplane:**
```bash
multipass shell controlplane
```

### 4.2 Thực nghiệm 1: Khởi tạo và Default Deny

**Mục đích:** Thiết lập môi trường sạch với `default-deny` — mọi traffic đều bị block, đây là điểm xuất phát.

**Bước 1 — Tạo namespace và các pods:**

```bash
kubectl create namespace production 2>/dev/null || true

kubectl apply -n production -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels:
    app: backend
spec:
  containers:
  - name: api
    image: nicolaka/netshoot
    command: ["nc", "-lk", "-p", "8080"]
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  containers:
  - name: web
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

kubectl -n production wait --for=condition=Ready pod/frontend pod/backend --timeout=90s
```

> **Giải thích:** `backend` chạy `nc -lk -p 8080` — netcat ở chế độ listen (-l), keep-alive (-k), port 8080. Đây là server giả lập đơn giản nhất để test TCP connectivity.

**Bước 2 — Tạo frontend2 và db-pod:**

```bash
kubectl run frontend2 -n production --image=nicolaka/netshoot \
  --labels="app=frontend2" -- sleep infinity

kubectl run db-pod -n production --image=nicolaka/netshoot \
  --labels="app=database" -- sleep infinity

kubectl -n production wait --for=condition=Ready pod/frontend2 pod/db-pod --timeout=60s
```

> **Giải thích:** `db-pod` đại diện cho một client không nên có quyền truy cập `backend` — dùng để kiểm chứng default-deny và union logic hoạt động đúng với pod không có rule nào.

**Bước 3 — Apply Default Deny:**

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
```

> **Giải thích:** `podSelector: {}` (empty selector) match tất cả pods trong namespace. Từ thời điểm này, mọi ingress vào bất kỳ pod nào trong `production` đều cần được cấp phép tường minh.

**Bước 4 — Lấy IP của backend và verify:**

```bash
BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
echo "Backend IP: $BACKEND_IP"

# Test — tất cả phải timeout (default deny đang active)
kubectl -n production exec frontend  -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ timeout
kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ timeout
kubectl -n production exec db-pod    -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ timeout
```

**Kết quả mong đợi:** Tất cả 3 lệnh đều timeout. Default deny đang hoạt động đúng.

---

### 4.3 Thực nghiệm 2: Chứng minh Union Logic

**Mục đích:** Thêm Policy A và Policy B từng bước một. Quan sát cách chúng cộng hưởng — không xung đột, không cancel.

**Bước 1 — Apply Policy A (Allow frontend → backend):**

```bash
kubectl apply -n production -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
EOF
```

> **Giải thích:** Policy này select pod có `app=backend` làm target. Mở ingress từ pod có `app=frontend` vào port 8080.

**Bước 2 — Verify sau Policy A:**

```bash
kubectl -n production exec frontend  -- nc -zv -w 5 $BACKEND_IP 8080  # ✅ Policy A cho phép
kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ Không có rule
kubectl -n production exec db-pod    -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ Không có rule
```

**Kết quả mong đợi:** Chỉ `frontend` thông. `frontend2` và `db-pod` vẫn bị block.

**Bước 3 — Apply Policy B (Allow frontend2 → backend):**

```bash
kubectl apply -n production -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend2
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend2
    ports:
    - protocol: TCP
      port: 8080
EOF
```

**Bước 4 — Verify sau Policy A + B đồng thời:**

```bash
kubectl -n production exec frontend  -- nc -zv -w 5 $BACKEND_IP 8080  # ✅ Policy A vẫn đúng
kubectl -n production exec frontend2 -- nc -zv -w 5 $BACKEND_IP 8080  # ✅ Policy B thêm vào
kubectl -n production exec db-pod    -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ Không có rule nào match
```

> **Đây là điểm cốt lõi của tập này:** Policy B được apply sau không làm mất đi quyền của Policy A. `frontend` vẫn thông. Hai policies cộng hưởng — đây là Union Logic.

**Bước 5 — Xem trạng thái tất cả policies:**

```bash
kubectl -n production get networkpolicy
# NAME             POD-SELECTOR   AGE
# allow-frontend   app=backend    2m
# allow-frontend2  app=backend    30s
# default-deny     <none>         5m
```

---

### 4.4 Thực nghiệm 3: Chứng minh giới hạn K8s NetworkPolicy và Explicit Deny với Calico

**Mục đích:** Chứng minh K8s NetworkPolicy chuẩn không thể deny tường minh. Sau đó dùng Calico GlobalNetworkPolicy để giải quyết.

**Bước 1 — Thử "deny" bằng cách xóa Policy B:**

```bash
kubectl delete -n production networkpolicy allow-frontend2

kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080
# ← timeout — frontend2 bị block vì không còn rule allow
```

> **Lưu ý:** Đây là implicit deny — không phải explicit deny. Frontend2 bị block không phải vì có rule "deny frontend2", mà vì không có rule nào "allow frontend2". Sự khác biệt này quan trọng khi thiết kế policy phức tạp.

**Bước 2 — Khôi phục Policy B và chuẩn bị test Calico:**

```bash
# Re-apply allow-frontend2
kubectl apply -n production -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend2
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend2
    ports:
    - protocol: TCP
      port: 8080
EOF

# Verify frontend2 vào được trước khi apply Calico GNP
kubectl -n production exec frontend2 -- nc -zv -w 5 $BACKEND_IP 8080  # ✅
```

**Bước 3 — Apply Calico GlobalNetworkPolicy với Explicit Deny:**

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-frontend2-explicit
spec:
  selector: app == 'backend' && projectcalico.org/namespace == 'production'
  order: 100
  ingress:
  - action: Deny
    source:
      selector: app == 'frontend2'
EOF
```

> **Giải thích chi tiết:**
> - `selector: app == 'backend' && projectcalico.org/namespace == 'production'` — GlobalNetworkPolicy là cluster-scoped, nên phải thêm namespace constraint để tránh ảnh hưởng các pod `app=backend` ở namespace khác.
> - `order: 100` — Calico đánh giá policy theo thứ tự order tăng dần. K8s NetworkPolicy chuẩn được ánh xạ sang order mặc định là 1000. Vì 100 < 1000, GlobalNetworkPolicy này được kiểm tra **trước** K8s NetworkPolicy.
> - `action: Deny` — Gói tin từ `frontend2` đến `backend` sẽ bị DROP ngay tại đây, không tiếp tục xuống các rule order 1000 (K8s NetworkPolicy allow-frontend2).

**Bước 4 — Verify Explicit Deny hoạt động:**

```bash
kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ Deny bởi Calico GNP!
kubectl -n production exec frontend  -- nc -zv -w 5 $BACKEND_IP 8080  # ✅ Frontend không bị ảnh hưởng
kubectl -n production exec db-pod    -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ Implicit deny (không có rule)
```

**Kết quả mong đợi:**
- `frontend2` bị block ngay lập tức (explicit deny, không phải timeout)
- `frontend` vẫn thông bình thường
- `db-pod` timeout (implicit deny — không liên quan đến Calico GNP)

> **Điểm khác biệt quan trọng:**
> - `frontend2`: Explicit Deny — Calico GNP order 100 drop packet chủ động
> - `db-pod`: Implicit Deny — không có rule allow nào match, packet bị drop do K8s default-deny

---

### 4.5 Dọn dẹp

```bash
kubectl -n production delete networkpolicy --all
kubectl delete globalnetworkpolicy deny-frontend2-explicit 2>/dev/null || true
kubectl -n production delete pod frontend2 db-pod 2>/dev/null || true
```

---

## 5. Tóm tắt kiến thức

### 5.1 Bảng tổng hợp hành vi

| Trạng thái | frontend → backend | frontend2 → backend | db-pod → backend |
|---|---|---|---|
| Default deny, không có policy | ❌ | ❌ | ❌ |
| + Policy A (allow-frontend) | ✅ | ❌ | ❌ |
| + Policy B (allow-frontend2) | ✅ | ✅ | ❌ |
| + Calico GNP deny-frontend2 | ✅ | ❌ (explicit) | ❌ (implicit) |

### 5.2 Nguyên tắc cốt lõi

1. **K8s NetworkPolicy là Allowlist thuần túy.** Không có `action: Deny`. Không có thứ tự rule. Không có conflict.

2. **Union Logic = cộng hưởng, không ghi đè.** Policy A + Policy B = tổng hợp quyền của A và B. Không thể dùng Policy B để thu hồi quyền Policy A đã cấp.

3. **Implicit Deny vs Explicit Deny:**
   - Implicit: Không có rule allow → traffic bị block (K8s default behavior khi có policy select pod)
   - Explicit: Có rule `action: Deny` → traffic bị drop chủ động (chỉ có ở Calico/CiliumNetworkPolicy)

4. **Khi cần Explicit Deny:** Dùng Calico `GlobalNetworkPolicy` với `order < 1000` để đảm bảo Deny rule được đánh giá trước K8s NetworkPolicy.

### 5.3 Khi nào dùng gì

| Bài toán | Giải pháp |
|---|---|
| Mở cổng cho service A truy cập service B | K8s NetworkPolicy (allow-only) |
| Nhiều teams cần cấp quyền độc lập | K8s NetworkPolicy — union logic đảm bảo không conflict |
| Chặn riêng một IP/Pod cụ thể | Calico GlobalNetworkPolicy với `action: Deny` |
| Policy ưu tiên cao toàn cluster (baseline) | Calico GlobalNetworkPolicy với `order < 1000` |
| Audit tất cả policies đang active | `kubectl get networkpolicy -A` + `kubectl get globalnetworkpolicy` |

---

## 6. Câu hỏi kiểm tra

Trả lời không cần nhìn tài liệu:

1. Một Pod đang có 3 NetworkPolicy select nó. Policy X allow port 80, Policy Y allow port 443, Policy Z allow port 22. Port 8080 có được mở không? Tại sao?

2. Bạn muốn sau khi apply Policy B, Pod `backend` **chỉ** nhận traffic từ `frontend2` (không còn nhận từ `frontend` nữa). Dùng K8s NetworkPolicy chuẩn có làm được không? Nếu không, làm thế nào?

3. Calico GlobalNetworkPolicy với `order: 500` và K8s NetworkPolicy, cái nào được đánh giá trước?

4. `projectcalico.org/namespace == 'production'` trong Calico selector để làm gì? Bỏ đi có sao không?

5. Sự khác biệt giữa implicit deny và explicit deny trong ngữ cảnh vận hành là gì?

<details>
<summary>Đáp án</summary>

1. **Không.** Port 8080 không được mở vì không có policy nào allow port 8080. Union của 3 policies chỉ mở port 80, 443, 22.

2. **Không làm được bằng K8s NetworkPolicy chuẩn.** Policy B không thể thu hồi quyền của Policy A. Giải pháp: Xóa Policy A (remove allow-frontend) **và** dùng Calico GlobalNetworkPolicy với `action: Deny` để explicit deny frontend nếu cần chặn chủ động.

3. **Calico GlobalNetworkPolicy order 500** được đánh giá trước vì 500 < 1000 (order mặc định của K8s NetworkPolicy trong Calico).

4. **Giới hạn scope của GlobalNetworkPolicy trong namespace `production`.** Bỏ đi thì policy áp dụng cho tất cả pods có label `app=backend` trên toàn cluster — có thể ảnh hưởng các namespace khác.

5. **Implicit deny:** Traffic bị drop vì không có rule allow nào khớp — không có log entry rõ ràng, khó debug. **Explicit deny:** Traffic bị drop bởi rule cụ thể — có thể log, audit, và intent rõ ràng trong codebase policy.

</details>

---

## 7. Tập tiếp theo

**Tập 16 — BGP trong Calico:** Biến K8s cluster thành một Autonomous System (AS) thực thụ, thiết lập BGP peering trực tiếp với ToR switch trong datacenter. Đây là kiến trúc networking được dùng trong production datacenter lớn.
