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
  Bug 2: toFQDNs cache stale (CDN IP rotate)
         → Old IP allowed, new IP blocked → intermittent!
```

---

## Bug 1: Quên allow DNS — Tại sao nguy hiểm

```
toFQDNs flow (khi đúng):
  Pod muốn gọi httpbin.org:
  1. DNS query → coredns:53 (ALLOWED)
  2. coredns trả về IP: 34.239.x.x
  3. Cilium DNS proxy intercept response
  4. Cilium ghi nhớ: "httpbin.org = 34.239.x.x"
  5. BPF policy: allow pod → 34.239.x.x:80
  6. Connection thành công!

toFQDNs flow (khi quên allow DNS):
  1. DNS query → coredns:53 (DROPPED by egress policy!)
  2. DNS resolve fail → "Could not resolve host"
  3. Cilium không có IP nào → toFQDNs rule vô nghĩa
  4. Connection fail — ngay cả khi có toFQDNs rule!

→ Hubble: DNS DROPPED → root cause rõ ràng!
```

---

## Policy với Bug 1: Thiếu DNS rule

```yaml
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
```

---

## Debug Bug 1 với Hubble

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Watch DNS flows
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

# → Root cause ngay:
#   DNS blocked → không resolve được → toFQDNs vô nghĩa
```

---

## Fix Bug 1: Add DNS allow rule

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: payment-egress
spec:
  endpointSelector:
    matchLabels:
      app: payment-service
  egress:
  # Fix: Allow DNS đến kube-dns
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
        - matchPattern: "httpbin.org"

  # Allow FQDN traffic
  - toFQDNs:
    - matchName: "httpbin.org"
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

---

## Bug 2: Stale DNS cache — Intermittent failure

```
CDN DNS rotation (ví dụ CloudFront, Fastly):
  t=0s:  httpbin.org → 34.239.x.x  (IP A)
  t=60s: httpbin.org → 52.201.x.x  (IP B — CDN rotates!)

Cilium tracking:
  t=0s:  Cache: {httpbin.org: [IP A], TTL: 30s}
  t=30s: TTL expire → Cilium re-resolve → update cache
         Cache: {httpbin.org: [IP B]}

Vấn đề nếu App caches DNS lâu hơn TTL:
  App cache: {httpbin.org: IP A} (không expire sớm)
  t=60s: App gọi IP A → nhưng Cilium chỉ allow IP B
  BPF policy: "IP A không trong allow list" → DROP

→ Intermittent: lúc IP match, lúc không!
→ Hubble: specific IP → DROPPED
```

---

## Debug Bug 2: cilium fqdn cache list

```bash
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium -o name | head -1)

# Xem IPs Cilium đang track
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache list

# Output:
# httpbin.org
#   IPs: 34.239.x.x, 52.201.x.x   ← Multiple IPs tracked
#   TTL: 45s remaining

# Nếu app cache IP cũ mà không trong list
# → Hubble sẽ show drop cho IP đó

# Force refresh:
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium fqdn cache clean --matchpattern "httpbin.org"
```

---

## toFQDNs Checklist trước khi deploy

| Check | Lý do |
| :--- | :--- |
| DNS port 53 allowed? | Nếu không → resolve fail → toFQDNs vô nghĩa |
| DNS matchPattern khớp domain? | Cần include cả subdomain nếu CDN dùng CNAME |
| TTL domain target là bao nhiêu? | CDN thường 60-300s, align app cache theo |
| Hubble observe DNS sau apply? | Verify DNS query FORWARDED |
| `cilium fqdn cache list`? | Verify IPs đang được track |

```
Debugging order:
  1. hubble observe --verdict DROPPED
  2. Thấy DNS DROPPED → Bug 1 (thêm DNS rule)
  3. Thấy specific IP DROPPED → Bug 2 (fqdn cache)
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Deploy toFQDNs với 2 bugs, debug với Hubble

Chúng ta sẽ thực hành:

1. **Test baseline** internet access (không có policy).
2. **Apply policy Bug 1:** toFQDNs thiếu DNS rule → Hubble show DNS DROPPED.
3. **Fix Bug 1:** thêm DNS allow rule → verify FORWARDED.
4. **Simulate Bug 2:** `cilium fqdn cache list` → hiểu stale IP mechanism.
5. **Force refresh cache** và verify behavior.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 41):** Cilium Lab 4 — WireGuard MTU với Cilium, Hubble show "MTU exceeded" (không cần ping test!).
