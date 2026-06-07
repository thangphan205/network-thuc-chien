# Lab Tập 38: Cilium Lab 2 — L7 Policy thiếu HTTP method, HTTP 403 & quy trình confirm dev

Tập này thực hành debug Cilium L7 policy bug: policy chỉ allow GET, thiếu POST, developer nhận 403. Học cách phân biệt 403 từ Cilium (Envoy) vs 403 từ app, và dùng Hubble xác nhận root cause.

## 🛠 Yêu cầu chuẩn bị
- Cilium + Hubble đang chạy (từ Tập 24).
- Cluster 3 nodes (controlplane, worker1, worker2).

---

## 🔬 Thí nghiệm 1: Deploy HTTP server và test baseline

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Tạo namespace và deploy pods:
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
     - name: app
       image: hashicorp/http-echo
       args: ["-listen=:8080", "-text=Hello from backend"]
       ports:
       - containerPort: 8080
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: frontend
     labels:
       app: frontend
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF

   kubectl -n production wait --for=condition=Ready \
     pod/backend pod/frontend --timeout=90s

   BACKEND_IP=$(kubectl -n production get pod backend \
     -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   ```

2. Verify baseline: tất cả methods đều work (chưa có policy):
   ```bash
   # GET
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "GET: %{http_code}\n" \
     http://$BACKEND_IP:8080/api/users
   # GET: 200

   # POST
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "POST: %{http_code}\n" \
     -X POST http://$BACKEND_IP:8080/api/users \
     -H "Content-Type: application/json" -d '{}'
   # POST: 200

   # DELETE
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "DELETE: %{http_code}\n" \
     -X DELETE http://$BACKEND_IP:8080/api/users/1
   # DELETE: 200
   ```

---

## 💥 Thí nghiệm 2: Apply L7 policy có bug — chỉ allow GET

**Trên `controlplane`:**

1. Apply policy thiếu POST:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: backend-l7
   spec:
     endpointSelector:
       matchLabels:
         app: backend
     ingress:
     - fromEndpoints:
       - matchLabels:
           app: frontend
       toPorts:
       - ports:
         - port: "8080"
           protocol: TCP
         rules:
           http:
           - method: GET       # CHỈ GET — thiếu POST!
             path: "/.*"
   EOF
   ```

2. Test lại sau khi apply policy:
   ```bash
   # GET vẫn OK
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "GET: %{http_code}\n" \
     http://$BACKEND_IP:8080/api/users
   # GET: 200 ✅

   # POST bị 403 — đây là bug dev báo cáo
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "POST: %{http_code}\n" \
     -X POST http://$BACKEND_IP:8080/api/users \
     -H "Content-Type: application/json" -d '{"name":"test"}'
   # POST: 403 ← Dev nhận được đây!
   ```

3. Kiểm tra backend có nhận được request không:
   ```bash
   kubectl -n production logs backend
   # Nếu output rỗng hoặc chỉ thấy GET logs →
   # → Backend KHÔNG thấy POST request
   # → Block ở network layer (Cilium), không phải app
   ```

---

## 🔬 Thí nghiệm 3: Xác định 403 từ Cilium hay từ App

**Trên `controlplane`:**

1. Dùng `curl -v` để xem response headers:
   ```bash
   kubectl -n production exec frontend -- \
     curl -v -X POST http://$BACKEND_IP:8080/api/users \
     -H "Content-Type: application/json" \
     -d '{"name":"test"}' 2>&1 | grep -E "< |^< "
   
   # Output:
   # < HTTP/1.1 403 Forbidden
   # < content-length: 15
   # < content-type: text/plain
   # < x-envoy-upstream-service-time: 1
   # < server: envoy                    ← KEY INDICATOR
   # < date: ...
   ```

2. Phân tích kết quả:
   ```
   "server: envoy" → Cilium L7 policy block
   Backend app KHÔNG nhận request (không có log)

   Nếu là app error:
   "server: hashicorp/http-echo" → App xử lý và trả 403
   Backend CÓ log request

   → Proof cho developer:
   "403 do Cilium network policy, không phải bug code.
    Backend chưa nhận request của bạn."
   ```

3. Verify qua Cilium policy:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium policy get | grep -A 20 "backend-l7"
   # Xem rule chỉ có method: GET → confirm thiếu POST
   ```

---

## 🔬 Thí nghiệm 4: Debug với Hubble và fix policy

**Trên `controlplane`:**

1. Setup Hubble và observe L7 flows:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2

   # Observe HTTP flows
   hubble observe \
     --namespace production \
     --protocol http \
     --follow &
   HUBBLE_PID=$!
   ```

2. Trigger request và đọc Hubble output:
   ```bash
   kubectl -n production exec frontend -- \
     curl -s -X POST http://$BACKEND_IP:8080/api/users \
     -H "Content-Type: application/json" -d '{}' &>/dev/null

   sleep 2
   # Hubble output:
   # production/frontend → production/backend:8080
   # HTTP POST /api/users → 403
   # Verdict: DROPPED  Reason: Policy denied (L7)
   
   # Đây là evidence đầy đủ để report cho developer
   ```

3. Fix: thêm POST vào policy:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: backend-l7
   spec:
     endpointSelector:
       matchLabels:
         app: backend
     ingress:
     - fromEndpoints:
       - matchLabels:
           app: frontend
       toPorts:
       - ports:
         - port: "8080"
           protocol: TCP
         rules:
           http:
           - method: GET
             path: "/.*"
           - method: POST        # ← Thêm POST
             path: "/api/.*"     # Chỉ /api/*, không phải /admin/*
   EOF
   ```

4. Verify fix và security boundary còn nguyên:
   ```bash
   # POST bây giờ OK
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "POST /api/users: %{http_code}\n" \
     -X POST http://$BACKEND_IP:8080/api/users \
     -d '{}'
   # POST /api/users: 200 ✅

   # DELETE vẫn bị block — đúng security policy
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "DELETE: %{http_code}\n" \
     -X DELETE http://$BACKEND_IP:8080/api/users/123
   # DELETE: 403 ✅ Đúng! DELETE không được phép

   # POST /admin/* vẫn bị block (chỉ allow /api/*)
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "POST /admin: %{http_code}\n" \
     -X POST http://$BACKEND_IP:8080/admin/users \
     -d '{}'
   # POST /admin: 403 ✅ Đúng! /admin/* không được phép

   # Hubble confirm:
   # POST /api/users → 200 FORWARDED
   kill $HUBBLE_PID 2>/dev/null
   pkill -f "port-forward" 2>/dev/null || true
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete ciliumnetworkpolicy backend-l7
kubectl -n production delete pod backend frontend
```

---

## ✅ Tổng kết

1. **Phân biệt 403 từ Cilium vs App:** Header `server: envoy` = Cilium L7 block, backend không nhận request. Header từ app framework = app logic. Kiểm tra backend logs cũng xác nhận: không có log = network layer block.
2. **Hubble L7 visibility:** `hubble observe --protocol http` show đầy đủ method, path, response code, verdict — đủ evidence để xác nhận với developer mà không cần tcpdump hay log diving.
3. **L7 policy whitelist principle:** Chỉ explicitly allow những gì cần (GET không tự động include POST). Mỗi method phải khai báo riêng. Khi thêm method mới: phải update CiliumNetworkPolicy explicitly.
4. **Policy update không cần restart:** `kubectl apply CiliumNetworkPolicy` → Cilium cập nhật Envoy listener config trong <100ms → request tiếp theo nhận policy mới ngay, không restart frontend hay backend.
