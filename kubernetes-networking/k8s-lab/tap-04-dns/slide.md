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

# Tập 4
## CoreDNS & Thuế "ndots:5": Tại sao mỗi request trong K8s tốn 5 DNS query?

**Phần 0 — Nền tảng K8s Networking** · `#CoreDNS` `#DNS` `#ndots` `#performance`

---

## Mục tiêu tập này

- Giải thích cơ chế phân giải tên miền trong K8s (FQDN vs short name)
- Đo được số DNS query thực tế bằng `tcpdump` và `dig`
- Cấu hình `dnsConfig` để giảm thuế ndots
- Triển khai NodeLocal DNSCache (`169.254.20.10`)

**Prerequisites:** Cluster từ Tập 1, Flannel đang chạy, CoreDNS hoạt động

---

## /etc/resolv.conf trong mọi Pod K8s

```bash
kubectl exec pod-a -- cat /etc/resolv.conf
# nameserver 10.96.0.10           ← ClusterIP của CoreDNS
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5
```

**3 dòng quyết định tất cả:**

| Dòng | Ý nghĩa |
| :--- | :--- |
| `nameserver 10.96.0.10` | Mọi DNS query đều đến CoreDNS trước |
| `search ...` | Danh sách domain tự thêm vào khi tên ngắn |
| `options ndots:5` | Nếu < 5 dấu chấm → thử search list trước |

---

## Thuế ndots:5 — Demo đếm query

```
Gọi: api.external.com  (2 dấu chấm → nhỏ hơn 5 → thử search list)

Query 1: api.external.com.default.svc.cluster.local  → NXDOMAIN ❌
Query 2: api.external.com.svc.cluster.local          → NXDOMAIN ❌
Query 3: api.external.com.cluster.local              → NXDOMAIN ❌
Query 4: api.external.com.                           → SUCCESS  ✅

3 query thừa mỗi lần gọi external service!

Gọi: nginx (không có dấu chấm → thử search list)

Query 1: nginx.default.svc.cluster.local  → SUCCESS ✅ (Service trong namespace)
(1 query — hiệu quả cho internal service)

Gọi: nginx.default.svc.cluster.local. (FQDN với dấu chấm cuối)
Query 1: nginx.default.svc.cluster.local.  → SUCCESS ✅ (1 query duy nhất)
```

---

## CoreDNS: Cơ chế phân giải nội bộ

**Service DNS pattern:**
```
<service>.<namespace>.svc.cluster.local
nginx.default.svc.cluster.local → 10.96.123.45 (ClusterIP)

Headless Service (clusterIP: None):
nginx-headless.default.svc.cluster.local → 10.244.1.5, 10.244.2.7 (Pod IPs)
```

**CoreDNS Corefile (cách cấu hình):**
```bash
kubectl -n kube-system get configmap coredns -o yaml | grep -A30 "Corefile"
# .:53 {
#   errors
#   health { lameduck 5s }
#   ready
#   kubernetes cluster.local in-addr.arpa ip6.arpa {
#     pods insecure
#     fallthrough in-addr.arpa ip6.arpa
#   }
#   forward . /etc/resolv.conf { max_concurrent 1000 }
#   cache 30
#   reload
#   loadbalance
# }
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Tối ưu hoá K8s DNS

Chúng ta sẽ thực hành các bước sau trong phần Lab:

1. **Phân tích "Thuế ndots":** Dùng `tcpdump` để đo lường số lượng DNS query thừa khi truy cập external domain.
2. **Tối ưu DNS với FQDN & dnsConfig:** Áp dụng giải pháp giảm tải DNS bằng FQDN và cấu hình `ndots:2`.
3. **Triển khai NodeLocal DNSCache:** Cài đặt DaemonSet DNS Cache trên từng Node và xác minh hiệu quả.
4. **Kiểm tra Headless Service:** Quan sát cách phân giải IP của các Pod đứng sau Headless Service mà không thông qua ClusterIP.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

**ndots:5 costs:**
```
Internal call (nginx): 1 query  ✅
External call (api.external.com): 4 queries (3 wasted) ❌
External FQDN (api.external.com.): 1 query ✅
```

**3 cách giảm DNS overhead:**

| Cách | Scope | Effort |
| :--- | :--- | :--- |
| Thêm `.` cuối FQDN | Per request | Thủ công |
| `dnsConfig: ndots: 2` | Per Pod | Low |
| NodeLocal DNSCache | Toàn cluster | Medium |

**Debug DNS:**
```bash
tcpdump -i any -n udp port 53        # Bắt DNS packets
kubectl exec pod -- nslookup <name>  # Test resolution
kubectl exec pod -- dig +stats <name> # Thấy query time
```

> **Tập tiếp theo:** CNI specification — ai thực sự cắm mạng cho Pod?
