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

# Tập 22
## Lab 1: Bẫy "Pod thiếu label" — Connection Timeout không rõ lý do

**Phần 2 — Calico Labs** · `#lab` `#label` `#NetworkPolicy` `#debug` `#calico`

---

## Tình huống thực tế

```
Thứ Hai, 9 giờ sáng. Developer gửi ticket:
"Tôi deploy backend mới. Frontend không gọi được backend.
 kubectl logs không có error. Không biết vấn đề ở đâu."

Thông tin:
- Cluster production đang chạy Calico
- Default deny đang active trong namespace
- Frontend → Backend qua Service port 8080
- curl từ frontend: timeout sau 30 giây
```

**Bạn là người xử lý — bắt đầu debug.**

---

## Setup Lab

```bash
multipass shell k8s-master
kubectl create namespace production 2>/dev/null || true

# NetworkPolicy đang active (default deny + allow frontend)
kubectl apply -n production -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend           # Áp dụng cho backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend      # Từ frontend
    ports:
    - {protocol: TCP, port: 8080}
EOF

# Developer deploy backend MỚI — nhưng quên label!
kubectl run backend-v2 -n production --image=nicolaka/netshoot \
  -- nc -lk -p 8080          # Không có --labels="app=backend"!

# Frontend Pod (có đủ labels)
kubectl run frontend -n production --image=nicolaka/netshoot \
  --labels="app=frontend" -- sleep infinity

kubectl -n production wait --for=condition=Ready pod/backend-v2 pod/frontend --timeout=60s
```

---

## Debug bước 1: Xác nhận vấn đề

```bash
BACKEND_IP=$(kubectl -n production get pod backend-v2 -o jsonpath='{.status.podIP}')

# Xác nhận symptom
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080
# (timeout sau 30 giây) ← Confirmed

# Kiểm tra cơ bản: Pod có running không?
kubectl -n production get pods -o wide
# NAME         READY   STATUS    IP            NODE
# backend-v2   1/1     Running   10.244.2.15   k8s-worker2  ← Pod OK
# frontend     1/1     Running   10.244.1.8    k8s-worker1

# Network connectivity cơ bản (không phải policy issue)?
kubectl -n production exec frontend -- ping -c 2 $BACKEND_IP
# 2 packets received ← Ping OK → Connectivity không phải vấn đề
# → Vấn đề là ở policy tầng TCP/port
```

---

## Debug bước 2: Kiểm tra labels

```bash
# Xem policy đang select Pod nào
kubectl -n production get networkpolicy allow-frontend-to-backend -o yaml
# podSelector: matchLabels: {app: backend}
# → Policy select Pod có label app=backend

# Kiểm tra labels của backend-v2
kubectl -n production get pod backend-v2 --show-labels
# NAME         LABELS
# backend-v2   <none>   ← KHÔNG CÓ LABEL!

# So sánh với Pod có label đúng
kubectl -n production get pod frontend --show-labels
# NAME       LABELS
# frontend   app=frontend,run=frontend

# Kết luận: backend-v2 KHÔNG match podSelector của policy
# → Felix KHÔNG tạo allow rule cho backend-v2
# → Default deny áp dụng → timeout
```

---

## Fix và Verify

```bash
# Fix: Add label cho backend-v2
kubectl -n production label pod backend-v2 app=backend

# Verify labels
kubectl -n production get pod backend-v2 --show-labels
# LABELS: app=backend  ← Label được add ngay!

# Felix nhận event ngay lập tức (không cần restart gì)
# Trong log Felix:
# "Endpoint updated: backend-v2 now matches policy allow-frontend-to-backend"

# Test lại — ngay lập tức hoạt động!
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080
# Connection to 10.244.2.15 8080 port succeeded! ✅

# Test từ hướng khác: Pod không có label frontend không vào được
kubectl run attacker -n production --image=nicolaka/netshoot -- sleep infinity
kubectl -n production exec attacker -- nc -zv $BACKEND_IP 8080
# (timeout) ← Policy vẫn bảo vệ ✅
```

---

## Key Lessons

**Root Cause:**
```
backend-v2 không có label app=backend
→ NetworkPolicy podSelector không match
→ Felix không tạo rule allow cho backend-v2
→ Default deny áp dụng (pod bị select bởi default-deny policy)
→ Frontend timeout khi kết nối
```

**Felix Event-Driven:**
```
Thêm label → K8s API notify Felix
→ Felix recalculate ngay lập tức
→ iptables rule được thêm trong < 100ms
→ Không cần restart Pod hay Node
```

**Checklist debug "timeout" với Calico:**
```bash
1. kubectl get pod --show-labels           # Kiểm tra labels
2. kubectl get networkpolicy               # Policy đang active?
3. calicoctl get workloadendpoint          # Felix biết Pod không?
4. iptables -L cali-tw-<endpoint> -n       # Rule có tồn tại không?
```

> **Tập tiếp theo:** Lab 2 — BGP không quảng bá Pod CIDR, server vật lý không ping được Pod.
