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

# Tập 34
## DNS Policy với toFQDNs: Filter theo domain thay vì IP — CDN multi-IP trap

**Phần 3 — Cilium** · `#toFQDNs` `#DNS` `#egress` `#CDN` `#policy`

---

## Mục tiêu tập này

- Tại sao CIDR-based egress policy thất bại với CDN
- toFQDNs: Cilium track DNS → IP mapping tự động
- Cách Cilium intercept DNS để populate CIDR
- Lab: filter external API theo domain

---

## Vấn đề: CDN có hàng trăm IP

```
Scenario: Block egress, chỉ allow gọi api.stripe.com

Cách ngây thơ: CIDR
  egress:
  - toCIDR:
    - "54.187.174.169/32"   # IP của api.stripe.com hôm nay

Vấn đề:
  api.stripe.com → CDN (CloudFront/Fastly)
  → IP thay đổi mỗi vài phút (DNS TTL = 60s)
  → IP khác nhau cho từng region
  → Có thể 50-200 IPs khác nhau trong 1 ngày

  Bạn chỉ whitelist 1 IP → Pod fail lúc IP rotate!

Đây là "CDN multi-IP trap"
```

---

## toFQDNs: DNS-aware CIDR

```
Cilium intercept tất cả DNS query của Pod:
  1. Pod gọi: dns_resolve("api.stripe.com")
  2. DNS response: [54.187.174.169, 54.239.17.6, ...]
  3. Cilium capture response
  4. Auto-add IP list vào BPF policy map
  5. Pod nhận DNS response bình thường
  6. Pod connect đến IP → BPF allow (vì IP đã được add)

Khi TTL expire → IP xóa khỏi policy map
  → Cilium query DNS lại nếu Pod cần
  → Policy luôn track current IPs

Bạn chỉ cần viết:
  toFQDNs:
  - matchName: "api.stripe.com"
  → Cilium lo phần còn lại!
```

---

## Cilium DNS proxy: Cơ chế hoạt động

```
Normal DNS flow:
  Pod → UDP:53 → kube-dns → response → Pod

Cilium DNS proxy flow:
  Pod → UDP:53 → BPF intercept → Cilium DNS proxy
                                       ↓
                                  forward đến kube-dns
                                       ↓
                                  kube-dns → response
                                       ↓
                                  Cilium capture IPs
                                       ↓
                                  Update BPF policy map
                                       ↓
                                  Forward response → Pod

Transparent! Pod không biết proxy đang intercept.
```

---

## Lab Setup: Default deny egress

```bash
multipass shell k8s-master

# Deploy pod test với internet access cần thiết
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-client
  labels: {app: api-client}
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

kubectl wait --for=condition=Ready pod/api-client --timeout=60s

# Test: hiện tại có thể reach internet
kubectl exec api-client -- curl -s --max-time 5 \
  https://httpbin.org/ip
# {"origin": "..."}  ← Accessible
```

---

## Lab: Apply DNS egress policy

```bash
# Apply default deny egress + allow only specific FQDN
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: egress-fqdn-policy
spec:
  endpointSelector:
    matchLabels:
      app: api-client
  egress:
  # Allow DNS (cần thiết để resolve domain)
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
  
  # Allow egress đến httpbin.org (Cilium auto-resolve)
  - toFQDNs:
    - matchName: "httpbin.org"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
      - port: "80"
        protocol: TCP
EOF
```

---

## Lab: Test FQDN policy

```bash
# Allow: httpbin.org
kubectl exec api-client -- curl -s --max-time 10 \
  http://httpbin.org/ip
# {"origin": "..."} ✅ ALLOWED

# Block: other domains (example.com)
kubectl exec api-client -- curl -s --max-time 5 \
  http://example.com
# curl: (28) Connection timed out ✅ BLOCKED

# Xem IPs Cilium đã resolve
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium -o name | head -1)

kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache list
# httpbin.org → [34.239.x.x, 54.175.x.x, ...]  ← IPs được track!
# TTL: 30s  ← Sẽ refresh tự động
```

---

## Lab: Xem DNS proxy events

```bash
# Observe DNS events
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium monitor --type drop --type l7

# Generate traffic để trigger DNS
kubectl exec api-client -- curl -s http://httpbin.org/ip &
kubectl exec api-client -- curl -s http://example.com &

# Monitor output:
# DNS proxy: httpbin.org → [34.x.x.x] (allowed)
# DNS proxy: example.com → [93.x.x.x] (not in policy)
# DROP: api-client:443 → 93.x.x.x (Policy denied)

# Hubble flow:
hubble observe --pod api-client --verdict DROPPED
# api-client → 93.x.x.x:80  DROPPED  Policy denied
```

---

## matchPattern vs matchName

```yaml
# matchName: exact domain
toFQDNs:
- matchName: "api.stripe.com"     # Chỉ api.stripe.com
                                   # KHÔNG match sub.api.stripe.com

# matchPattern: wildcard
toFQDNs:
- matchPattern: "*.stripe.com"    # Match mọi subdomain
                                   # api.stripe.com ✅
                                   # checkout.stripe.com ✅
                                   # stripe.com ❌ (cần thêm riêng)

# Kết hợp:
toFQDNs:
- matchName: "stripe.com"
- matchPattern: "*.stripe.com"    # Cover cả root và subdomain
```

---

## Key Takeaways

```
toFQDNs giải quyết CDN multi-IP problem:
  Bạn viết domain → Cilium track IPs tự động
  DNS TTL expire → Cilium refresh → policy luôn up-to-date

Cách hoạt động:
  Cilium DNS proxy intercept tất cả DNS
  → Capture IP từ DNS response
  → Update BPF policy map theo TTL

Gotchas:
  ⚠️  Phải allow DNS (port 53) trong egress policy!
      Không có DNS → FQDN không resolve → không vào được
  ⚠️  DNS policy cần matchPattern cho DNS allow
      Khác với toFQDNs matchName (trừ DNS proxy)
  ⚠️  matchName khác matchPattern:
      matchName = exact, matchPattern = wildcard (*)
```

> **Tập tiếp theo (Tập 35): Cilium + Istio — Khi nào kết hợp, khi nào dùng Cilium thuần?**
