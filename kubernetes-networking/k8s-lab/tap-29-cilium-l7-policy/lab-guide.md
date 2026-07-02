# Lab Tập 29: L7 Policy — Chặn HTTP POST theo path với Envoy Proxy

Tập này deploy HTTP server thực, apply CiliumNetworkPolicy với L7 HTTP rules, và verify rằng vi phạm policy trả về HTTP 403 (không phải timeout) thông qua Envoy proxy.

> **⚠️ Lưu ý về backend server:** `python3 -m http.server` chỉ implement `GET`/`HEAD` (`SimpleHTTPRequestHandler`) — **mọi request POST tới được backend sẽ trả 501 "Unsupported method"**, không phải 200. Đây không phải lỗi của policy hay Envoy: 403 nghĩa là Envoy chặn trước khi request chạm tới app; 501 nghĩa là request lọt qua được Envoy nhưng app tự nó không xử lý POST. Bài học ở đây là phân biệt **403 (Envoy block)** vs **không-403 — ví dụ 501 (request tới được backend, backend tự trả lỗi)**, không phải "403 vs 200".

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy với Hubble enabled (từ Tập 23).
- Không có NetworkPolicy nào trong namespace `production`.

---

## 🔬 Thực nghiệm 1: Deploy HTTP server và baseline test

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Deploy backend HTTP server và frontend client:
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
       image: python:3.11-alpine
       command: ["python3", "-m", "http.server", "8080"]
       workingDir: "/tmp"
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
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   ```

2. Baseline test — tất cả paths accessible trước khi có policy:
   ```bash
   # GET /
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "%{http_code}" http://$BACKEND_IP:8080/
   # 200 ← No policy, allowed

   # POST /admin/users (sẽ bị block sau khi apply policy)
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "%{http_code}" \
     -X POST http://$BACKEND_IP:8080/admin/users -d '{}'
   # 501 ← Chưa có L7 policy nên request tới được backend; 501 vì http.server không handle POST (không phải bị Cilium chặn)
   ```

---

## 💥 Thực nghiệm 2: Apply L7 policy và verify HTTP 403

**Trên `controlplane`:**

1. Apply CiliumNetworkPolicy với L7 HTTP rules:
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
             path: "/.*"             # Allow ALL GET requests
           - method: POST
             path: "/api/.*"         # Allow POST chỉ /api/*
           # POST /admin/* không có rule → tự động DENY
   EOF
   ```

2. Test GET / — ALLOWED:
   ```bash
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "%{http_code}" http://$BACKEND_IP:8080/
   # 200 ✅ GET allowed
   ```

3. Test POST /api/data — ALLOWED (đi qua được Envoy, backend tự trả 501 vì không handle POST):
   ```bash
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "%{http_code}" \
     -X POST http://$BACKEND_IP:8080/api/data -d '{}'
   # 501 ✅ Envoy cho qua (path match /api/.*) — không phải 403 nên biết KHÔNG bị Cilium chặn.
   ```

4. Test POST /admin/users — BLOCKED với HTTP 403:
   ```bash
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -w "%{http_code}" \
     -X POST http://$BACKEND_IP:8080/admin/users -d '{}'
   # 403 ✅ Forbidden! (Envoy block, không phải timeout)

   # Xem response body:
   kubectl -n production exec frontend -- \
     curl -s -X POST http://$BACKEND_IP:8080/admin/users -d '{}'
   # Access denied  ← Envoy L7 block message
   ```

   *Nhận xét:* HTTP 403 thay vì timeout — developer thấy rõ lỗi là policy block, không phải service down. Đây là UX improvement so với L4 block.

---

## 🔬 Thực nghiệm 3: Verify Envoy proxy được sử dụng

**Trên `controlplane`:**

1. Verify Envoy listener được tạo khi có L7 policy:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list | grep backend
   # ENDPOINT  POLICY (ingress)  POLICY (egress)  ...
   # 1234      Enabled           Disabled
   ```
   > **💡 Lưu ý:** `POLICY (ingress) Enabled` chỉ cho biết endpoint này có ít nhất 1 CiliumNetworkPolicy L3/L4 áp dụng — **không chứng minh** L7/Envoy redirect đang hoạt động (1 policy L3/L4 thuần cũng cho `Enabled` y hệt). Bằng chứng thật cho L7 nằm ở bước 2 (`Proxy Status: ... redirects active`).

2. Xem Envoy listener config (nếu có cilium CLI support):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium status | grep -i "l7\|envoy\|proxy"
   # Proxy Status: OK, 1 redirects active
   # ← Envoy đang handle L7 redirect cho 1 endpoint — đây mới là bằng chứng L7 policy active!
   ```

3. So sánh latency L4 vs L7:
   ```bash
   # L4-only request (GET /) — direct path, no Envoy
   kubectl -n production exec frontend -- bash -c "
     for i in \$(seq 1 20); do
       curl -s -o /dev/null -w '%{time_total}\n' \
         http://$BACKEND_IP:8080/ 2>/dev/null
     done | awk '{sum+=\$1} END {printf \"L7 GET avg: %.3fs\n\", sum/NR}'
   "
   # L7 GET avg: 0.012s  ← Thêm Envoy hop nhưng vẫn nhanh
   ```

---

## 🔬 Thực nghiệm 4: Hubble observe HTTP flows

**Trên `controlplane`:**

1. Port-forward Hubble Relay:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2
   ```

2. Watch HTTP flows:
   ```bash
   hubble observe --server localhost:4245 --namespace production \
     --protocol http --follow &
   HUBBLE_PID=$!
   ```

3. Generate mixed traffic:
   ```bash
   # Allowed
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null http://$BACKEND_IP:8080/ &
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -X POST \
     http://$BACKEND_IP:8080/api/users -d '{}' &

   # Blocked
   kubectl -n production exec frontend -- \
     curl -s -o /dev/null -X POST \
     http://$BACKEND_IP:8080/admin/users -d '{}' &

   sleep 3
   kill $HUBBLE_PID 2>/dev/null

   # Hubble output:
   # production/frontend → production/backend  HTTP GET /             200 FORWARDED
   # production/frontend → production/backend  HTTP POST /api/users   501 FORWARDED  ← qua được Envoy, backend tự trả lỗi
   # production/frontend → production/backend  HTTP POST /admin/users 403 DROPPED    ← Envoy chặn trước khi tới backend
   ```

4. Xem DROPPED HTTP flows riêng:
   ```bash
   hubble observe --server localhost:4245 --namespace production \
     --verdict DROPPED --protocol http
   # production/frontend → production/backend:8080  HTTP POST /admin/users
   # 403  DROPPED  Policy denied
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete ciliumnetworkpolicies backend-l7
kubectl -n production delete pod backend frontend
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **L7 policy via Envoy sidecar-less:** Khi detect L7 rule, Cilium redirect traffic qua Envoy process chạy trên host network namespace — không inject container vào Pod, transparent với application.
2. **HTTP 403 thay vì timeout:** L7 block trả về HTTP 403 Forbidden ngay lập tức — developer nhìn thấy lỗi rõ ràng thay vì chờ timeout 30-60s và đoán nguyên nhân.
3. **Regex path matching:** `path: "/api/.*"` dùng regex Go — `.*` match mọi ký tự. Test regex kỹ trước khi apply production vì sai regex = policy không hoạt động như mong đợi.
4. **Hubble log HTTP L7 data:** `hubble observe --protocol http` hiển thị method + path + status code — không cần access log của application. Đây là visibility mà Calico + tcpdump không thể có.
