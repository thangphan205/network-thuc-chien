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

# Tập 40
## Cilium Lab 1: Pod label sai — Hubble show "Policy denied" ngay lập tức

**Phần 3 — Cilium Labs** · `#lab` `#label` `#hubble` `#CiliumNetworkPolicy` `#debug`

---

## Tình huống thực tế

```
Cùng scenario như Tập 22 (Calico Lab 1)
nhưng lần này với Cilium + Hubble:

Developer deploy backend-v2, quên label.
Frontend không gọi được backend.

Với Calico (Tập 22):
  Debug mất 5-10 phút:
  kubectl get pod --show-labels
  kubectl get networkpolicy
  iptables -L ...

Với Cilium + Hubble:
  hubble observe --verdict DROPPED
  → "Policy denied" xuất hiện ngay
  Debug: 30 giây!

Lab này: thực hành quy trình debug với Hubble
```

---

## Lab Setup

```bash
multipass shell k8s-master

kubectl create namespace production 2>/dev/null || true

# Apply default deny + allow policy (chỉ allow app=backend)
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
      app: backend           # Policy match app=backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - {protocol: TCP, port: 8080}
EOF

# Backend-v2: QUÊN LABEL (bug)
kubectl run backend-v2 -n production \
  --image=nicolaka/netshoot -- nc -lk -p 8080

# Frontend (đủ label)
kubectl run frontend -n production \
  --image=nicolaka/netshoot \
  --labels="app=frontend" -- sleep infinity

kubectl -n production wait --for=condition=Ready \
  pod/backend-v2 pod/frontend --timeout=60s
```

---

## Debug với Hubble: 30 giây

```bash
BACKEND_IP=$(kubectl -n production get pod backend-v2 \
  -o jsonpath='{.status.podIP}')

# Step 1: Start Hubble observer TRƯỚC KHI trigger
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
sleep 2

hubble observe --namespace production \
  --verdict DROPPED --follow &
HUBBLE_PID=$!

# Step 2: Trigger vấn đề
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080

# Step 3: Hubble output ngay lập tức:
# production/frontend → production/backend-v2:8080
# DROPPED  Policy denied

# Không cần: kubectl logs, tcpdump, iptables -L
# Vấn đề đã rõ: Policy denied!
```

---

## Debug: Tại sao policy denied?

```bash
# Hubble nói "Policy denied" → Policy không match backend-v2
# Kiểm tra labels:
kubectl -n production get pod backend-v2 --show-labels
# NAME        LABELS
# backend-v2  <none>   ← Không có label!

# Policy yêu cầu: app=backend
# backend-v2 không có label này → không match → default deny

# Verify với Cilium:
CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
  -o name | head -1)

kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium endpoint list | grep backend-v2
# ENDPOINT  POLICY-INGRESS  IDENTITY  POD NAME
# 2345      Enabled         99999     backend-v2
# Identity 99999 = không label → không match policy allow-frontend

# So sánh:
# Nếu có label app=backend → identity khác → match policy → ALLOW
```

---

## Fix và Verify với Hubble

```bash
# Fix: Add label
kubectl -n production label pod backend-v2 app=backend

# Verify Hubble thấy FORWARDED ngay
# (không cần restart gì!)
kubectl -n production exec frontend -- nc -zv $BACKEND_IP 8080

# Hubble output:
# production/frontend → production/backend-v2:8080
# FORWARDED   ← Thay đổi ngay!

# Verify Cilium identity update
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium endpoint list | grep backend-v2
# ENDPOINT  POLICY-INGRESS  IDENTITY
# 2345      Enabled         7891    ← Identity thay đổi vì label thay đổi!
# Identity 7891 = {app=backend} → match policy → ALLOW

kill $HUBBLE_PID
```

---

## Cilium vs Calico: Debug speed comparison

```
Cùng scenario, cùng bug (missing label):

Calico debug flow:
  1. kubectl exec frontend -- nc -zv ... (xác nhận timeout 30s)
  2. kubectl get pod --show-labels (tìm label)
  3. kubectl get networkpolicy (đọc selector)
  4. calicoctl get wep (xem Felix biết pod không)
  5. iptables -L cali-tw-<endpoint> (xem rule tồn tại không)
  Time: 5-15 phút

Cilium debug flow:
  1. hubble observe --verdict DROPPED
     → "Policy denied" ngay lập tức
  2. kubectl get pod --show-labels
     → Thấy label missing
  Time: 30-60 giây

Root cause identification:
  Calico: infer từ nhiều data sources
  Cilium: Hubble nói thẳng "DROPPED: Policy denied"
```

---

## Key Lessons

**Cilium Identity model trong action:**
```
Khi add label app=backend:
  1. K8s API notify cilium-agent
  2. cilium-agent recalculate identity
  3. Update cilium_lxc BPF map: endpoint → new identity
  4. Policy map lookup: identity → ALLOW rule match!
  5. Next packet → BPF lookup → FORWARDED

Total time: < 100ms (same as Calico)
```

**Debug workflow với Hubble:**
```
Nghi ngờ connectivity issue?
  Step 1: hubble observe --verdict DROPPED
  Step 2: Đọc "reason" field
    "Policy denied" → Label/policy issue
    "No route to host" → Routing issue
    "Connection refused" → App issue (không phải network)
  Step 3: Fix và watch Hubble realtime confirm
```

> **Tập tiếp theo (Tập 41): Cilium Lab 2 — L7 Policy thiếu HTTP method, HTTP 403 và quy trình confirm dev.**
