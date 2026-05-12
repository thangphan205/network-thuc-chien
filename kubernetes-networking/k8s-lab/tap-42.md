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

# Tập 42
## Cilium Lab 3: DNS Egress Policy & toFQDNs trap — External API fail bí ẩn

**Phần 3 — Cilium Labs** · `#lab` `#toFQDNs` `#DNS` `#egress` `#trap`

---

## Tình huống thực tế

```
Backend team báo:
"Chúng tôi gọi external payment API (api.stripe.com).
 Lúc hoạt động, lúc không.
 Random failure, không tái hiện được.
 Code không thay đổi gì."

DevOps đã implement egress policy với toFQDNs.
Lỗi xảy ra sau khi apply policy.

2 bugs cùng lúc:
  Bug 1: Quên allow DNS port 53 trong egress
         → DNS resolve fail → Connection fail
  Bug 2: toFQDNs cache stale (IP thay đổi, cache chưa update)
         → Cũ IP bị allow, IP mới bị block → intermittent!

Lab này demo cả 2 bugs này.
```

---

## Lab Setup

```bash
multipass shell k8s-master

# Deploy payment service pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: payment-service
  labels: {app: payment-service}
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

kubectl wait --for=condition=Ready pod/payment-service --timeout=60s

# Test ban đầu: internet accessible
kubectl exec payment-service -- \
  curl -s --max-time 5 https://httpbin.org/ip
# {"origin": "..."} ← Works
```

---

## Apply policy với Bug 1: Quên allow DNS

```bash
# Bug 1: Policy có toFQDNs nhưng quên allow port 53
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: payment-egress
spec:
  endpointSelector:
    matchLabels:
      app: payment-service
  egress:
  # BUG: Không có rule cho DNS (port 53)!
  - toFQDNs:
    - matchName: "httpbin.org"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
      - port: "80"
        protocol: TCP
EOF

# Test: fail! Vì không resolve được domain
kubectl exec payment-service -- \
  curl -s --max-time 5 http://httpbin.org/ip
# curl: (6) Could not resolve host: httpbin.org
```

---

## Debug Bug 1 với Hubble

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Observe DNS drops
hubble observe \
  --from-pod default/payment-service \
  --verdict DROPPED \
  --follow &

# Trigger request
kubectl exec payment-service -- \
  curl --max-time 5 http://httpbin.org/ip &>/dev/null

# Hubble output:
# default/payment-service → kube-system/coredns:53
# DROPPED  Policy denied
# ← DNS query bị block!
# Payment service không resolve được httpbin.org
# → Cilium không track IP → toFQDNs không có gì để allow

# → Root cause rõ ngay: DNS bị block!
```

---

## Fix Bug 1: Add DNS allow

```bash
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: payment-egress
spec:
  endpointSelector:
    matchLabels:
      app: payment-service
  egress:
  # Fix: Allow DNS
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      rules:
        dns:
        - matchPattern: "*.httpbin.org"
        - matchPattern: "httpbin.org"
  
  # Allow FQDN traffic
  - toFQDNs:
    - matchName: "httpbin.org"
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
EOF

# Test fix
kubectl exec payment-service -- \
  curl -s --max-time 10 http://httpbin.org/ip
# {"origin": "..."} ✅ FIXED!
```

---

## Bug 2: Stale DNS cache (intermittent)

```bash
# Verify DNS resolution và IP tracking
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium -o name | head -1)

# Xem IPs Cilium đang track cho httpbin.org
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache list
# httpbin.org → [34.239.x.x]  TTL: 30s remaining

# Simulate: IP thay đổi (CDN rotate)
# Nếu real IP rotate trong production:
# 1. DNS response trả về IP mới (ví dụ: 52.201.x.x)
# 2. Cilium nhận DNS response → update cache
# 3. Nếu TTL cache chưa expire → old entry vẫn tồn tại 1 thời gian
# 4. App dùng IP cũ (cached ở app level) → traffic đến IP không trong policy
# 5. BPF policy: "IP này không được allow" → DROP

# Debug: Xem Hubble show IP bị drop
hubble observe --from-pod default/payment-service \
  --verdict DROPPED
# payment-service → 52.201.x.x:80  DROPPED (new IP not in policy!)
```

---

## Fix Bug 2: DNS TTL alignment

```bash
# Cách Cilium handle stale:
# Cilium theo TTL từ DNS response
# Nếu TTL = 60s → Cilium giữ IP trong 60s → auto-expire → re-resolve

# Verify TTL tracking
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache list
# httpbin.org
#   IPs: 34.239.x.x, 52.201.x.x   ← Multiple IPs tracked!
#   TTL: 45s (from DNS response)

# Force refresh (nếu suspect stale)
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache clean --matchpattern "httpbin.org"

# Verify re-resolve
kubectl exec payment-service -- curl http://httpbin.org/ip &>/dev/null
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache list
# httpbin.org → [new IPs]  ← Fresh resolve!
```

---

## Key Lessons: toFQDNs Checklist

```
Trước khi apply toFQDNs policy, check:

1. DNS port 53 allowed?
   Nếu không: DNS resolve fail → toFQDNs không có IP → DROP ALL

2. DNS matchPattern trong rule?
   rules.dns.matchPattern phải include tất cả domains trong toFQDNs

3. TTL của domain target là bao nhiêu?
   CDN (Fastly/CloudFront): TTL thường 60-300s
   → Cilium refresh đúng TTL
   → App không nên cache IP lâu hơn DNS TTL

4. Test với Hubble sau apply:
   hubble observe --protocol dns → DNS allowed?
   hubble observe --from-pod ... --verdict DROPPED → IP blocked?

5. Check fqdn cache:
   cilium fqdn cache list → IPs đang được track
```

---

## Key Takeaways

```
2 bugs trong toFQDNs policy:

Bug 1 (thường gặp): Quên allow DNS
  Symptom: "Could not resolve host"
  Hubble: DNS query → coredns DROPPED
  Fix: Add DNS egress rule với matchPattern

Bug 2 (khó bắt): Stale IP / CDN rotation
  Symptom: Intermittent connection fail
  Hubble: Specific IP → DROPPED (IP mới CDN rotate)
  Fix: Cilium tự handle qua TTL
       App không nên long-cache DNS responses

Debugging order:
  1. hubble observe --verdict DROPPED
  2. Nếu thấy DNS DROPPED → Bug 1
  3. Nếu thấy random IP DROPPED → Bug 2 (check fqdn cache)
```

> **Tập tiếp theo (Tập 43): Cilium Lab 4 — WireGuard MTU với Cilium, Hubble show "MTU exceeded".**
