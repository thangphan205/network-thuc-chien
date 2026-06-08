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
  section.warn { background: linear-gradient(135deg, #1a0800 0%, #0d1021 100%); }
  section.warn h2 { color: #f87171; border-bottom-color: #f87171; }
---

<!-- _class: ep -->

# Tập 21
## Lab 4: Network Policy Nâng Cao với Calico

**Phần 2 — Calico Labs** · `#NetworkPolicy` `#GlobalNetworkPolicy` `#NetworkSet` `#egress` `#multi-tenant`

---

## Mục tiêu tập này

- Cô lập multi-tenant: namespace A không reach namespace B
- Kiểm soát egress: chỉ cho phép Pod gọi ra các IP cụ thể (NetworkSet)
- Áp rule cluster-wide bằng Calico `GlobalNetworkPolicy`
- Debug policy bằng iptables chains do Calico sinh ra

**Prerequisites:** Cluster Calico đang chạy (từ Tập 9), `calicoctl` đã cài

---

## Tình huống thực tế

```
Security audit yêu cầu:
"Cluster đang chạy SaaS multi-tenant.
 Tenant A và Tenant B phải hoàn toàn cô lập.
 Backend chỉ được gọi ra payment gateway (1.1.1.1).
 Không Pod nào được reach AWS IMDS (169.254.169.254)
 — vector tấn công để lấy IAM credentials."

Hiện trạng:
- Không có NetworkPolicy nào → mọi Pod reach mọi Pod
- backend-a curl ra 8.8.8.8, 1.2.3.4 thoải mái
- frontend-a curl được frontend-b (cross-tenant)
```

---

<!-- _class: warn -->

## Bẫy phổ biến: Egress Deny làm chết DNS

```
Thêm egress deny-all trước khi mở port 53:

  frontend-a → nslookup kubernetes.default → TIMEOUT

Thứ tự BẮT BUỘC:
  1. Mở port 53 (UDP + TCP) egress TRƯỚC
  2. Sau đó mới thêm deny-all còn lại

Vì K8s NetworkPolicy không có "allow implicit" với DNS.
Khi có bất kỳ egress rule nào → chỉ traffic match rule đó được ra.
Port 53 không được mention = bị block = mọi hostname resolve thất bại.
```

---

## Ba công cụ Calico vượt qua giới hạn K8s NetworkPolicy

```
1. NetworkSet — tập hợp CIDR/IP tái sử dụng được:
   apiVersion: projectcalico.org/v3
   kind: NetworkSet
   metadata: { name: allowed-egress-ips, namespace: tenant-a }
   spec:
     nets: [1.1.1.1/32]   ← payment gateway

2. Calico NetworkPolicy — dùng selector đến NetworkSet:
   egress:
   - action: Allow
     destination:
       selector: role == 'allowed-external'
   - action: Deny        ← block tất cả còn lại

3. GlobalNetworkPolicy — áp toàn cluster, không bị namespace giới hạn:
   kind: GlobalNetworkPolicy
   spec:
     order: 1            ← ưu tiên cao nhất
     selector: all()
     egress:
     - action: Deny
       destination: { nets: [169.254.169.254/32] }
```

---

## Security Matrix mục tiêu

| Nguồn | Đích | Kết quả |
|---|---|---|
| `frontend-a` (tenant-a) | `frontend-b` (tenant-b) | ❌ BLOCK |
| `frontend-a` (tenant-a) | `backend-a` (tenant-a) | ✅ ALLOW |
| `backend-a` | `1.1.1.1` (payment GW) | ✅ ALLOW |
| `backend-a` | `8.8.8.8` (Google DNS) | ❌ BLOCK |
| Bất kỳ Pod nào | `169.254.169.254` (IMDS) | ❌ BLOCK |
| Bất kỳ Pod nào | `kube-dns` port 53 | ✅ ALLOW |

---

<!-- _class: lab -->

## 🔬 Lab Time: Multi-Tenant Isolation + Egress Control

Chúng ta sẽ thực hành:

1. **Setup:** Tạo hai namespace `tenant-a`, `tenant-b` với workload tương ứng.
2. **Verify ban đầu:** Xác nhận tất cả đang thông (chưa có policy).
3. **Thử thách 30 phút tự giải:** Tự thiết kế và áp đủ 5 policy đạt security matrix.
4. **Hướng dẫn từng bước:** Đối chiếu default-deny, DNS whitelist, NetworkSet, GlobalNetworkPolicy.
5. **Verify toàn bộ:** Chạy security matrix test tổng thể.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Tập 22 — Tổng kết & Workflow Troubleshooting Calico chuẩn
