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

# Tập 31
## DNS Policy với toFQDNs: Filter theo domain — CDN multi-IP trap

**Phần 3 — Cilium** · `#toFQDNs` `#DNS` `#egress` `#CDN` `#policy`

---

## Mục tiêu tập này

- Tại sao CIDR-based egress policy thất bại với CDN
- toFQDNs: Cilium track DNS → IP mapping tự động
- Cách Cilium intercept DNS để populate CIDR policy
- matchName vs matchPattern — exact vs wildcard

**Prerequisites:** Cilium đang chạy (từ Tập 24), cluster có internet access

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
  → IP khác nhau cho mỗi region
  → Có thể 50-200 IPs khác nhau trong 1 ngày

  Bạn chỉ whitelist 1 IP → Pod fail lúc IP rotate!
  → "CDN multi-IP trap"
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
  6. Pod connect → BPF ALLOW (IP đã được add)

Khi TTL expire → Cilium refresh tự động
  → Policy luôn track current IPs

Bạn chỉ cần viết:
  toFQDNs:
  - matchName: "api.stripe.com"
  → Cilium lo phần còn lại!
```

---

## Cilium DNS proxy: Cơ chế

```
Normal DNS:
  Pod → UDP:53 → kube-dns → response → Pod

Cilium DNS proxy:
  Pod → UDP:53 → BPF intercept → Cilium DNS proxy
                                       │ forward
                                  kube-dns → response
                                       │ capture IPs
                                  Update BPF policy map
                                       │
                                  Forward response → Pod

Transparent! Pod không biết proxy đang intercept.
Policy: phải allow UDP:53 egress riêng
```

---

## matchName vs matchPattern

```yaml
# matchName: exact domain (case-insensitive)
toFQDNs:
- matchName: "api.stripe.com"     # Chỉ api.stripe.com
                                   # KHÔNG match sub.api.stripe.com

# matchPattern: wildcard (glob)
toFQDNs:
- matchPattern: "*.stripe.com"    # Match mọi subdomain
                                   # api.stripe.com ✅
                                   # checkout.stripe.com ✅
                                   # stripe.com ❌ (cần thêm riêng)

# Cover cả root và subdomain:
toFQDNs:
- matchName: "stripe.com"
- matchPattern: "*.stripe.com"

# QUAN TRỌNG: DNS allow cần matchPattern riêng!
```

---

## Gotchas: Phải allow DNS trước

```yaml
# SAI: không allow DNS → FQDN không resolve → blocked hoàn toàn
egress:
- toFQDNs:
  - matchName: "httpbin.org"    # Policy đúng nhưng...
  # ← Không allow UDP:53 → DNS fail → Pod không connect được!

# ĐÚNG: phải allow DNS TRƯỚC
egress:
- toEndpoints:
  - matchLabels:
      k8s-app: kube-dns
      k8s:io.kubernetes.pod.namespace: kube-system
  toPorts:
  - ports:
    - port: "53"
      protocol: UDP
    rules:
      dns:
      - matchPattern: "*.httpbin.org"   # DNS allow specific pattern
      - matchPattern: "httpbin.org"

- toFQDNs:
  - matchName: "httpbin.org"    # FQDN egress allow
  toPorts:
  - ports:
    - {port: "443", protocol: TCP}
    - {port: "80", protocol: TCP}
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Apply toFQDNs egress policy

Chúng ta sẽ thực hành:

1. **Deploy api-client pod** và verify có thể reach internet ban đầu.
2. **Apply default deny egress** — verify không reach được đâu.
3. **Apply toFQDNs policy** — allow chỉ httpbin.org, block example.com.
4. **Verify `cilium fqdn cache list`** — thấy IPs Cilium đã track từ DNS.
5. **Hubble observe DNS proxy events** — thấy allowed/blocked domains.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 32):** Cilium + Istio — Khi nào kết hợp, khi nào dùng Cilium thuần?
