# Lab Tập 23: Lab 4 — Cross-namespace AND/OR Bug

Tập này thực hành gỡ lỗi (troubleshooting) kịch bản "Bẫy kép" (Bug Masking) trong chính sách chéo namespace (cross-namespace policy): lỗi thiếu nhãn namespace vô tình che giấu lỗi nghiêm trọng về logic OR thay vì AND.

### Sơ đồ so sánh cú pháp logic: AND vs OR trong Kubernetes NetworkPolicy

```mermaid
graph TD
  subgraph OR_Logic [1. Lỗi cấu hình OR Logic có hai dấu gạch ngang]
    direction TB
    A["ingress:"]
    B["- from:"]
    C["  - namespaceSelector:<br/>      matchLabels:<br/>        name: monitoring"]
    D["  - podSelector:<br/>      matchLabels:<br/>        role: prometheus"]
    
    A --> B
    B --> C
    B --> D
    
    ResultOR["KẾT QUẢ: Cho phép bất kỳ Pod nào thuộc monitoring<br/>HOẶC bất kỳ Pod nào có nhãn role: prometheus ở bất kỳ đâu.<br/>(Quá rộng - Lỗ hổng bảo mật!)"]
    C & D -.-> ResultOR
  end

  subgraph AND_Logic [2. Cấu hình AND Logic chính xác chỉ có một gạch ngang]
    direction TB
    E["ingress:"]
    F["- from:"]
    G["  - namespaceSelector:<br/>      matchLabels:<br/>        name: monitoring<br/>    podSelector:<br/>      matchLabels:<br/>        role: prometheus"]
    
    E --> F
    F --> G
    
    ResultAND["KẾT QUẢ: Chỉ cho phép Pod có nhãn role: prometheus<br/>VÀ nằm trong namespace monitoring.<br/>(Bảo mật tối đa!)"]
    G -.-> ResultAND
  end
  
  classDef default fill:#151530,stroke:#2a2050,color:#e2e8f0;
  class ResultOR fill:#2d080a,stroke:#f87171,color:#ff8a8a;
  class ResultAND fill:#0a2d0a,stroke:#34d399,color:#a7f3d0;
```

---

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 9.
- Không có NetworkPolicy nào trong `production`.

---

## 🔬 Thí nghiệm 1: Setup môi trường với 2 bugs được plant sẵn

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Tạo namespaces — **cố tình KHÔNG label namespace monitoring** (Bug 2):
   ```bash
   kubectl create namespace monitoring 2>/dev/null || true
   kubectl create namespace production 2>/dev/null || true

   # KHÔNG chạy: kubectl label namespace monitoring name=monitoring
   # (đây là Bug 2 cần debug)
   ```

2. Verify namespace không có label:
   ```bash
   kubectl get namespace monitoring --show-labels
   # NAME        LABELS
   # monitoring  kubernetes.io/metadata.name=monitoring   ← Không có name=monitoring custom label
   ```

   > [!TIP]
   > **Pro Tip về Kubernetes Auto-Labeling:**
   > Kể từ Kubernetes v1.21+, Kubernetes tự động gắn nhãn mặc định `kubernetes.io/metadata.name: <namespace-name>` cho tất cả các namespace. 
   > Do đó, trong thực tế production hiện đại, ta không cần gắn nhãn custom `name: monitoring` thủ công, mà có thể trỏ thẳng trực tiếp `namespaceSelector` vào nhãn mặc định này để tránh phát sinh lỗi quên gắn nhãn:
   > ```yaml
   > namespaceSelector:
   >   matchLabels:
   >     kubernetes.io/metadata.name: monitoring
   > ```
   > Tuy nhiên, bài lab này cố tình thiết lập theo cách viết nhãn custom cổ điển để minh họa hoàn hảo kịch bản "Bẫy kép" (Bug Masking) thường gặp trên thực tế.

3. Deploy backend với metrics endpoint:
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

4. Deploy Prometheus (legit):
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

5. Deploy rogue pod trong monitoring (không có role=prometheus):
   ```bash
   kubectl run rogue -n monitoring --image=nicolaka/netshoot -- sleep infinity
   ```

6. Chờ ready và ghi IPs:
   ```bash
   kubectl -n production wait --for=condition=Ready pod/backend --timeout=60s
   kubectl -n monitoring wait --for=condition=Ready pod/prometheus pod/rogue --timeout=60s
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   ```

---

## 💥 Thí nghiệm 2: Apply policy với 2 bugs và reproduce symptom

**Trên `controlplane`:**

1. Apply default deny:
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

2. Apply policy với cả 2 bugs:
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
             name: monitoring      # Bug 2: namespace chưa có label này!
       - podSelector:              # Bug 1: Dấu "-" → OR thay vì AND!
           matchLabels:
             role: prometheus
       ports:
       - protocol: TCP
         port: 9090
   EOF
   ```

3. Reproduce — Prometheus vẫn timeout:
   ```bash
   kubectl -n monitoring exec prometheus -- nc -zv -w 3 $BACKEND_IP 9090
   # (timeout) ← Cả 2 bugs ngăn cản
   ```

---

## 🔬 Thí nghiệm 3: Debug Bug 2 — Namespace thiếu label

**Trên `controlplane`:**

1. **Đọc policy kỹ:**
   ```bash
   kubectl -n production get networkpolicy allow-prometheus-metrics -o yaml | grep -A10 "ingress:"
   # ingress:
   # - from:
   #   - namespaceSelector:
   #       matchLabels:
   #         name: monitoring    ← Chờ label này
   #   - podSelector:
   #       matchLabels:
   #         role: prometheus
   ```

2. **Kiểm tra namespace labels:**
   ```bash
   kubectl get namespace monitoring --show-labels
   # NAME        LABELS
   # monitoring  kubernetes.io/metadata.name=monitoring
   # ← Không có "name=monitoring"! Đây là Bug 2
   ```

3. **Hiểu hậu quả:**
   ```
   namespaceSelector: {name: monitoring} không match namespace nào
   → Item 1 trong from list = empty set (không match Pod nào)
   → Chỉ Item 2 còn tác dụng: podSelector: {role: prometheus}
   → Any pod với role=prometheus trong BẤT KỲ namespace đều được vào!
   → Nhưng Prometheus vẫn timeout vì...
   ```

4. **Kiểm tra nhanh — Rogue pod có vào được không?**
   ```bash
   kubectl -n monitoring exec rogue -- nc -zv -w 3 $BACKEND_IP 9090
   # (timeout) ← Bug 2 đang mask Bug 1 (namespace không match → rule vô hiệu)
   ```

---

## 🔬 Thí nghiệm 4: Debug Bug 1 — OR thay vì AND

**Trên `controlplane`:**

1. **Fix Bug 2 trước** — thêm label namespace:
   ```bash
   kubectl label namespace monitoring name=monitoring
   ```

2. **Ngay lập tức test — Rogue pod thể hiện Bug 1:**
   ```bash
   kubectl -n monitoring exec rogue -- nc -zv $BACKEND_IP 9090
   # Connection succeeded! ← BUG 1 lộ ra! Rogue (không có role=prometheus) vào được!
   ```
   *Đây là lý do phải fix CẢ HAI bugs.*

3. **Phân tích YAML cẩn thận:**
   ```yaml
   from:
   - namespaceSelector:    # Dấu "-" → Item 1 (OR với Item 2)
       matchLabels:
         name: monitoring
   - podSelector:          # Dấu "-" → Item 2 (OR với Item 1)
       matchLabels:
         role: prometheus
   ```
   ```
   OR logic:
   - Bất kỳ Pod nào trong namespace monitoring vào được (match Item 1)
   - Bất kỳ Pod có role=prometheus trong ANY namespace vào được (match Item 2)
   ```

---

## 🔬 Thí nghiệm 5: Fix cả 2 bugs đúng cách

**Trên `controlplane`:**

1. Apply policy đúng — **AND logic** (không có dấu `-` thừa):
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
             name: monitoring   # Namespace phải là monitoring
         podSelector:           # ← KHÔNG có dấu "-" = AND!
           matchLabels:
             role: prometheus   # VÀ Pod phải là prometheus
       ports:
       - protocol: TCP
         port: 9090
   EOF
   ```

2. Test matrix đầy đủ:
   ```bash
   # Prometheus (legit) — phải qua ✅
   kubectl -n monitoring exec prometheus -- nc -zv $BACKEND_IP 9090
   # Connection succeeded! ✅

   # Rogue (monitoring namespace, không có role=prometheus) — phải bị chặn ✅
   kubectl -n monitoring exec rogue -- nc -zv -w 3 $BACKEND_IP 9090
   # (timeout) ✅ Đúng!

   # Test pod với role=prometheus nhưng namespace khác — phải bị chặn ✅
   kubectl run fake-prom --image=nicolaka/netshoot \
     --labels="role=prometheus" -- sleep infinity
   kubectl wait --for=condition=Ready pod/fake-prom --timeout=30s
   FAKE_IP=$(kubectl get pod fake-prom -o jsonpath='{.status.podIP}')
   kubectl exec fake-prom -- nc -zv -w 3 $BACKEND_IP 9090
   # (timeout) ✅ Đúng! Sai namespace dù có đúng label
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete networkpolicy default-deny allow-prometheus-metrics
kubectl -n production delete pod backend
kubectl -n monitoring delete pod prometheus rogue
kubectl delete pod fake-prom 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **2 bugs mask nhau:** Bug 2 (thiếu namespace label) làm policy không hoạt động → Bug 1 (OR) không lộ ra. Fix Bug 2 trước khi fix Bug 1 sẽ tạo security hole thực sự.
2. **Phải fix cả hai cùng lúc:** Xóa dấu `-` thừa (AND) + thêm namespace label.
3. **Test matrix bắt buộc sau mỗi policy:** Test legit pod, rogue pod cùng namespace, pod với label đúng nhưng namespace sai.
4. **Checklist verification:**
   ```bash
   kubectl get namespace <ns> --show-labels      # Verify namespace labels
   # Đếm dấu "-" trong YAML from block           # AND vs OR
   # Test rogue pod từ cùng namespace            # Verify không quá rộng
   ```
