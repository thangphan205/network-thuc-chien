# Lab Tập 15: Union Logic — NetworkPolicy như Security Group

Tập này chứng minh NetworkPolicy là allowlist thuần túy: nhiều policies cộng hưởng, không có cancel, không có priority.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 9.
- Namespace `production` với `backend` pod từ Tập 14 (hoặc tạo lại bên dưới).

---

## 🔬 Thí nghiệm 1: Setup — Default deny và tạo thêm pods

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Đảm bảo namespace và backend pod tồn tại:
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

2. Tạo thêm frontend2 và db-pod:
   ```bash
   kubectl run frontend2 -n production --image=nicolaka/netshoot \
     --labels="app=frontend2" -- sleep infinity
   kubectl run db-pod -n production --image=nicolaka/netshoot \
     --labels="app=database" -- sleep infinity
   kubectl -n production wait --for=condition=Ready pod/frontend2 pod/db-pod --timeout=60s
   ```

3. Apply default deny ingress:
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

4. Ghi lại backend IP:
   ```bash
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   ```

---

## 🔬 Thí nghiệm 2: Thêm policies từng bước và verify union

**Trên `controlplane`:**

1. Không có policy allow → tất cả bị deny:
   ```bash
   kubectl -n production exec frontend -- nc -zv -w 2 $BACKEND_IP 8080   # ❌
   kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080  # ❌
   ```

2. Apply Policy A — Allow frontend → backend:
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

   ```bash
   kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080    # ✅ Policy A
   kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080  # ❌ Không có rule
   ```

3. Apply Policy B — Allow frontend2 → backend:
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

4. Cả hai policies active đồng thời:
   ```bash
   kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080    # ✅ Policy A vẫn đúng
   kubectl -n production exec frontend2 -- nc -zv $BACKEND_IP 8080   # ✅ Policy B thêm vào
   # Policy A KHÔNG bị Policy B ghi đè!
   ```

5. Xem tất cả policies đang active:
   ```bash
   kubectl -n production get networkpolicy
   # NAME            POD-SELECTOR   AGE
   # allow-frontend  app=backend    30s
   # allow-frontend2 app=backend    10s
   # default-deny    <none>         2m
   ```

---

## 🔬 Thí nghiệm 3: Chứng minh không có DENY tường minh

**Trên `controlplane`:**

1. Cố "deny" frontend2 bằng cách xóa policy B:
   ```bash
   kubectl delete -n production networkpolicy allow-frontend2
   kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080
   # (timeout) ← frontend2 bị deny vì không còn rule allow
   ```

2. Thử viết policy "deny" tường minh — **K8s NetworkPolicy không hỗ trợ:**
   ```bash
   # Không có action: Deny trong K8s NetworkPolicy chuẩn!
   # Chỉ có: from/to selectors + ports → implicit allow
   ```

3. Demo Calico GlobalNetworkPolicy với DENY tường minh:
   ```bash
   # Re-apply allow-frontend2 trước
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

   # Verify frontend2 vào được
   kubectl -n production exec frontend2 -- nc -zv $BACKEND_IP 8080   # ✅

   # Apply Calico GlobalNetworkPolicy để DENY frontend2 explicitly
   cat <<'EOF' | kubectl apply -f -
   apiVersion: projectcalico.org/v3
   kind: GlobalNetworkPolicy
   metadata:
     name: deny-frontend2-explicit
   spec:
     selector: app == 'backend'
     order: 100
     ingress:
     - action: Deny
       source:
         selector: app == 'frontend2'
   EOF

   # frontend2 bị chặn bởi Calico GlobalNetworkPolicy
   kubectl -n production exec frontend2 -- nc -zv -w 2 $BACKEND_IP 8080   # ❌ Deny!
   # frontend vẫn OK (không bị ảnh hưởng bởi deny policy)
   kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080           # ✅
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete networkpolicy --all
kubectl delete globalnetworkpolicy deny-frontend2-explicit 2>/dev/null || true
kubectl -n production delete pod frontend2 db-pod 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Union logic = cộng hưởng, không có ghi đè:** Policy A + Policy B = allow cả A và B. Không có priority, không có cancel.
2. **Không có DENY tường minh trong K8s NetworkPolicy:** Chỉ có "không có allow" = implicit deny. Muốn explicit DENY phải dùng Calico GlobalNetworkPolicy hoặc AdminNetworkPolicy (K8s 1.29+).
3. **Giống Security Group:** Mỗi policy mở thêm một cổng — tổng hợp tất cả. Không như firewall ACL có thứ tự và DENY tường minh.
4. **Calico mở rộng:** `action: Deny` trong GlobalNetworkPolicy cho phép deny tường minh với `order` để kiểm soát ưu tiên.
