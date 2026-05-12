---
marp: true
theme: default
paginate: true
style: |
  section { font-family: 'Segoe UI', sans-serif; font-size: 22px; background: #0d1021; color: #e2e8f0; }
  h1 { color: #a78bfa; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #34d399; font-size: 1.4em; border-bottom: 2px solid #34d399; padding-bottom: 0.2em; }
  h3 { color: #fbbf24; font-size: 1.1em; }
  code { background: #1a1a35; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1a1a35; border-left: 4px solid #a78bfa; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
  th { background: #2d1b69; color: #e9d5ff; padding: 10px 14px; font-weight: 600; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a2050; color: #e2e8f0; background: #151530; }
  tr:nth-child(even) td { background: #1e1e40; }
  blockquote { border-left: 4px solid #fbbf24; padding-left: 16px; color: #cbd5e1; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  pre .hljs-comment, pre .hljs-meta { color: #7dd3fc; }
  pre .hljs-keyword, pre .hljs-selector-tag { color: #f9a8d4; }
  pre .hljs-string, pre .hljs-attr { color: #86efac; }
  pre .hljs-number, pre .hljs-literal { color: #fde68a; }
  pre .hljs-variable, pre .hljs-template-variable { color: #c4b5fd; }
  pre .hljs-built_in, pre .hljs-name { color: #67e8f9; }
  pre .hljs-subst { color: #e2e8f0; }
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 41
## Cilium Lab 2: L7 Policy thiếu HTTP method — HTTP 403 & quy trình confirm dev

**Phần 3 — Cilium Labs** · `#lab` `#L7` `#HTTP403` `#envoy` `#debug`

---

## Tình huống thực tế

```
Security team yêu cầu:
"Frontend chỉ được phép GET /api/*
 Không được POST/PUT/DELETE"

DevOps implement Cilium L7 policy.
Dev test thấy: POST /api/users → 403 Forbidden

Dev tạo ticket:
"Tôi gọi POST /api/users nhưng bị 403.
 Không có lỗi ở code. Backend cũng không log gì.
 API spec rõ ràng cho phép POST!"

→ DevOps phải confirm: 403 do policy, không phải bug code
```

---

## Lab Setup: HTTP server + L7 policy sai

```bash
multipass shell k8s-master

kubectl create namespace production 2>/dev/null || true

# Backend: simple HTTP echo server
kubectl apply -n production -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend
  labels: {app: backend}
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
  labels: {app: frontend}
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

kubectl -n production wait --for=condition=Ready \
  pod/backend pod/frontend --timeout=60s

BACKEND_IP=$(kubectl -n production get pod backend \
  -o jsonpath='{.status.podIP}')
```

---

## Apply L7 Policy với BUG (thiếu POST)

```bash
# Policy có bug: chỉ allow GET, quên POST
kubectl apply -n production -f - <<EOF
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

# Test GET (OK)
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  http://$BACKEND_IP:8080/api/users
# 200 ✅

# Test POST (BUG — dev bị 403)
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://$BACKEND_IP:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}'
# 403 ← Dev nhận được đây!
```

---

## Debug: Xác nhận 403 do Cilium, không phải app

```bash
# Quan trọng: 403 từ Envoy (Cilium) hay từ backend app?
# → Kiểm tra Response headers!

kubectl -n production exec frontend -- \
  curl -v -X POST http://$BACKEND_IP:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}' 2>&1 | grep -E "< |HTTP"

# Output:
# < HTTP/1.1 403 Forbidden
# < x-envoy-upstream-service-time: ...   ← Envoy header!
# < server: envoy                         ← Đây là Envoy, không phải app!

# → 403 từ Envoy = Cilium L7 policy block
# → Backend app chưa nhận được request!
```

---

## Debug với Hubble: Xác nhận L7 drop

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
sleep 2

# Xem L7 flows
hubble observe \
  --namespace production \
  --protocol http \
  --follow &

# Trigger request
kubectl -n production exec frontend -- \
  curl -s -X POST http://$BACKEND_IP:8080/api/users \
  -d '{}' &>/dev/null

# Hubble output:
# production/frontend → production/backend:8080
# HTTP POST /api/users  → 403
# Verdict: DROPPED
# Reason: Policy denied (L7)

# Đây là proof cho developer:
# "403 là do Cilium L7 policy, không phải backend code"
```

---

## Fix và Verify

```bash
# Fix: Thêm POST vào policy
kubectl apply -n production -f - <<EOF
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
        - method: POST         # ← Thêm dòng này!
          path: "/api/.*"      # Chỉ /api/*, không phải /admin/*
EOF

# Test POST lại
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://$BACKEND_IP:8080/api/users \
  -d '{}'
# 200 ✅ FIXED!

# Verify DELETE vẫn bị block (đúng ý security)
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE http://$BACKEND_IP:8080/api/users/123
# 403 ✅ Đúng! DELETE không được phép
```

---

## Quy trình xử lý ticket "403 lạ"

```
Developer báo: "POST /api/users → 403"

Step 1: Xác định 403 từ đâu (Envoy hay App?)
  Check response headers:
  "server: envoy" → Cilium policy
  "server: nginx"/"server: express" → App logic

Step 2: Xem Hubble L7 flows
  hubble observe --protocol http --verdict DROPPED
  → Thấy "Policy denied (L7)" → Cilium

Step 3: Review L7 policy
  kubectl get ciliumnetworkpolicy -n production -o yaml
  → Tìm method list → thiếu POST!

Step 4: Fix policy + communicate với developer
  "403 do Cilium network policy thiếu POST.
   Đã fix. Security review cần approve trước."

Step 5: Verify với Hubble sau fix
  hubble observe --protocol http → thấy 200
```

---

## Key Lessons

```
L7 Policy debugging pattern:

403 từ Cilium vs 403 từ App:
  Cilium 403: header "server: envoy", backend KHÔNG nhận request
  App 403: header từ app framework, backend LOG request

Hubble L7 fields:
  HTTP method, path, response code, verdict
  → Đủ thông tin để nói với dev: "policy blocked POST, not app"

Security workflow:
  Default: whitelist chỉ những gì cần
  Khi thêm method: phải explicit (GET mới không tự động include POST)
  Principle of least privilege cho HTTP methods

L7 policy update không restart Pod:
  kubectl apply CiliumNetworkPolicy
  → Cilium update Envoy listener config
  → Next request nhận config mới (<100ms)
  → Không cần restart frontend/backend
```

> **Tập tiếp theo (Tập 42): Cilium Lab 3 — DNS Egress Policy & toFQDNs trap, external API fail bí ẩn.**
