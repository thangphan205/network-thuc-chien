# Lab Tập 15: NetworkPolicy cơ bản — Default Deny và Ingress Policy

Tập này thực hành viết NetworkPolicy từ đầu với thứ tự đúng và test từng bước.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 11.
- Không có NetworkPolicy nào đang active trong namespace `production` (xóa nếu có từ tập trước).

---

## 🔬 Thí nghiệm 1: Deploy namespace và Pods

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Tạo namespace `production`:
   ```bash
   kubectl create namespace production 2>/dev/null || true
   ```

2. Deploy frontend, backend và Service:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: frontend
     labels:
       app: frontend
       tier: web
   spec:
     nodeName: worker1
     containers:
     - name: web
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: backend
     labels:
       app: backend
       tier: api
   spec:
     nodeName: worker2
     containers:
     - name: api
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "8080"]
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: backend-svc
   spec:
     selector:
       app: backend
     ports:
     - port: 8080
       targetPort: 8080
   EOF
   kubectl -n production wait --for=condition=Ready pod/frontend pod/backend --timeout=90s
   ```

3. Test baseline (không có policy → tất cả pass):
   ```bash
   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 port succeeded! ✅
   ```

---

## 🔬 Thí nghiệm 2: Apply Default Deny Ingress

**Trên `controlplane`:**

1. Apply default deny ingress cho toàn namespace:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny-ingress
   spec:
     podSelector: {}
     policyTypes:
     - Ingress
   EOF
   ```

2. Test — backend ingress bị deny:
   ```bash
   kubectl -n production exec frontend -- nc -zv -w 3 backend-svc 8080
   # (timeout) ← Backend ingress bị deny ✅
   ```

3. Apply allow rule cho frontend → backend:
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

4. Test lại — frontend được vào:
   ```bash
   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 succeeded! ✅
   ```

---

## 🔬 Thí nghiệm 3: Deploy attacker pod và verify bị chặn

**Trên `controlplane`:**

1. Deploy attacker pod (không có label app=frontend):
   ```bash
   kubectl run attacker -n production --image=nicolaka/netshoot -- sleep infinity
   kubectl -n production wait --for=condition=Ready pod/attacker --timeout=60s
   ```

2. Test từ attacker — phải bị chặn:
   ```bash
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   kubectl -n production exec attacker -- nc -zv -w 3 $BACKEND_IP 8080
   # (timeout) ← Attacker bị chặn ✅ (không có label app=frontend)
   ```

3. Test từ frontend — vẫn qua:
   ```bash
   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 succeeded! ✅
   ```

---

## 🔬 Thí nghiệm 4: Demo DNS break và fix

**Trên `controlplane`:**

1. Apply default deny egress (mạnh nhất):
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny-egress
   spec:
     podSelector: {}
     policyTypes:
     - Egress
   EOF
   ```

2. DNS bị break:
   ```bash
   kubectl -n production exec frontend -- nslookup backend-svc
   # ;; connection timed out; no servers could be reached ❌
   ```

3. Fix — Apply DNS allow rule **trước**:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-dns
   spec:
     podSelector: {}
     policyTypes:
     - Egress
     egress:
     - ports:
       - protocol: UDP
         port: 53
       - protocol: TCP
         port: 53
   EOF
   ```

4. DNS hoạt động trở lại:
   ```bash
   kubectl -n production exec frontend -- nslookup backend-svc
   # Name: backend-svc.production.svc.cluster.local ✅
   ```

5. Nhưng frontend → backend vẫn chưa được (egress bị deny):
   ```bash
   kubectl -n production exec frontend -- nc -zv -w 3 backend-svc 8080
   # (timeout) ← Egress từ frontend bị deny
   ```

6. Allow egress từ frontend đến backend:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-frontend-egress
   spec:
     podSelector:
       matchLabels:
         app: frontend
     policyTypes:
     - Egress
     egress:
     - to:
       - podSelector:
           matchLabels:
             app: backend
       ports:
       - protocol: TCP
         port: 8080
   EOF

   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 succeeded! ✅
   ```

---

## 🧹 Dọn dẹp (giữ namespace production cho tập tiếp)

```bash
kubectl -n production delete networkpolicy --all
kubectl -n production delete pod attacker
# Giữ frontend và backend cho Tập 16
```

---

## ✅ Tổng kết

1. **Không có policy = default allow:** Pod không bị select bởi bất kỳ policy nào thì không bị restrict gì.
2. **Thứ tự đúng:** Allow DNS trước → Allow egress cần thiết → Default deny ingress → Allow ingress cụ thể → Default deny egress.
3. **DNS must always be allowed:** Quên allow port 53 UDP/TCP → mọi DNS lookup fail → app không làm gì được.
4. **Test matrix:** Sau mỗi policy, test từng cặp source→dest để xác nhận đúng behavior.
