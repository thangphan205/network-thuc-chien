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

# Tập 39
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

## L7 Policy với Envoy: Cơ chế hoạt động

```
Cilium L7 Policy flow:
  Frontend → Port 8080

  Bước 1: BPF TC hook intercept packet
  Bước 2: Policy check: "có L7 rule không?"
           → Có → redirect sang Envoy sidecar-less

  Bước 3: Envoy kiểm tra:
    Method: POST
    Path: /api/users
    Match rule {method: GET}? → NO MATCH
    → Return 403 Forbidden

  Bước 4: Frontend nhận 403
           Backend KHÔNG nhận request!

Key: "server: envoy" header trong response
     = Cilium blocked, not app logic
```

---

## Policy có bug: Chỉ allow GET

```yaml
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
```

---

## Cách xác định 403 từ Cilium hay từ App

```bash
# Request với verbose output
kubectl -n production exec frontend -- \
  curl -v -X POST http://$BACKEND_IP:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}' 2>&1 | grep -E "< |HTTP"

# 403 từ Cilium (Envoy):
# < HTTP/1.1 403 Forbidden
# < server: envoy                ← KEY INDICATOR
# < x-envoy-upstream-service-time: 1ms

# 403 từ App:
# < HTTP/1.1 403 Forbidden
# < server: nginx               ← App framework
# < x-request-id: abc123        ← App generated

# "server: envoy" → Cilium block → backend KHÔNG nhận request
# → Bug là ở policy, không phải code
```

---

## Debug với Hubble: L7 flows

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
sleep 2

# Xem L7 HTTP flows (method, path, status code)
hubble observe \
  --namespace production \
  --protocol http \
  --follow &

# Trigger POST request
kubectl -n production exec frontend -- \
  curl -s -X POST http://$BACKEND_IP:8080/api/users \
  -d '{}' &>/dev/null

# Hubble output:
# production/frontend → production/backend:8080
# HTTP POST /api/users  → 403
# Verdict: DROPPED
# Reason: Policy denied (L7)

# Proof cho developer:
# "Cilium L7 policy blocked POST — not app code"
```

---

## Fix: Thêm POST vào policy

```yaml
# Sửa: Thêm method POST với path /api/*
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
        - method: POST      # ← Thêm dòng này!
          path: "/api/.*"   # Chỉ /api/*, không phải /admin/*
```

---

## Verify sau fix

```bash
# Test POST lại
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://$BACKEND_IP:8080/api/users \
  -d '{}'
# 200 ✅ FIXED!

# Verify DELETE vẫn bị block (đúng security policy)
kubectl -n production exec frontend -- \
  curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE http://$BACKEND_IP:8080/api/users/123
# 403 ✅ Đúng! DELETE không được phép

# Hubble confirm:
# POST /api/users → 200 FORWARDED  ✅
# DELETE /api/users/123 → 403 DROPPED (correct)
```

---

## Quy trình xử lý ticket "403 lạ"

| Bước | Action | Tool |
| :--- | :--- | :--- |
| 1 | Xác định 403 từ đâu | `curl -v` → check `server:` header |
| 2 | Confirm L7 drop | `hubble observe --protocol http` |
| 3 | Xem policy thiếu gì | `kubectl get ciliumnetworkpolicy -o yaml` |
| 4 | Fix + communicate | `kubectl apply` + thông báo dev |
| 5 | Verify | Hubble → 200 FORWARDED |

```
"server: envoy" = Cilium blocked
"server: nginx/express/..." = App blocked

Nguyên tắc:
  Nếu backend KHÔNG log request → network layer block
  Nếu backend CÓ log request → app logic block
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Deploy L7 policy bug, debug bằng Hubble

Chúng ta sẽ thực hành:

1. **Deploy** backend HTTP server + frontend + L7 policy chỉ allow GET.
2. **Reproduce bug:** POST → 403.
3. **Confirm nguồn gốc 403:** `curl -v` → check `server: envoy` header.
4. **Hubble debug:** `hubble observe --protocol http` → thấy "Policy denied (L7)".
5. **Fix policy:** thêm POST method → verify POST 200, DELETE vẫn 403.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 40):** Cilium Lab 3 — DNS Egress Policy & toFQDNs trap, external API fail bí ẩn.
