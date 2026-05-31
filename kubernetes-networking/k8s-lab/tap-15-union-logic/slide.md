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

# Tập 15 - Union Logic
## Union Logic: NetworkPolicy hoạt động như Security Group, không phải ACL

**Phần 2 — Calico** · `#NetworkPolicy` `#union-logic` `#allow-list` `#SecurityGroup`

![height:200px](https://www.tigera.io/app/uploads/2026/01/Calico-logo-2026-white-text.svg)

---

## Mục tiêu tập này

- Chứng minh nhiều NetworkPolicy cùng select 1 Pod = cộng hưởng (additive)
- Phân biệt NetworkPolicy (allowlist) vs ACL (có DENY tường minh)
- Demo không có cách "deny" cụ thể bằng NetworkPolicy chuẩn
- Giới thiệu Calico GlobalNetworkPolicy cho DENY tường minh

**Prerequisites:** Cluster Calico từ Tập 9-14

---

## Security Group vs ACL

**AWS Security Group (allow-only):**
```
SG-1: Allow port 80 from 10.0.1.0/24
SG-2: Allow port 443 from 0.0.0.0/0
SG-3: Allow port 22 from 10.0.0.5/32

Kết quả: Port 80, 443, 22 OPEN
         SG-1 không "ghi đè" SG-2
         Không có priority hay conflict
```

**AWS NACL (allow + deny):**
```
Rule 100: Allow port 80
Rule 200: Deny port 80 from 1.2.3.4
Rule 300: Allow all

NACL có thứ tự, rule thấp hơn thắng
DENY ghi đè ALLOW
```

**K8s NetworkPolicy = Security Group (not NACL)**

---

## Union Logic trong K8s NetworkPolicy

```yaml
# Policy A: Frontend → Backend port 8080
# Policy B: Frontend2 → Backend port 8080

# Kết quả cho Backend Pod (union của tất cả ingress rules):
# Allow: from frontend:   port 8080
# Allow: from frontend2:  port 8080

# KHÔNG có policy nào cancel policy kia!
# Không có "priority" hay "order"
# Tất cả đều ADDITIVE
```

**Hệ quả quan trọng:**
```
Bạn KHÔNG thể viết "deny port 80 from specific IP"
bằng K8s NetworkPolicy chuẩn.

Cách duy nhất để deny: KHÔNG CÓ rule allow cho traffic đó.
```

---

## Khi cần DENY tường minh — dùng Calico

```yaml
# Calico mở rộng: GlobalNetworkPolicy với action: Deny
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-frontend2-explicit
spec:
  selector: app == 'backend' && projectcalico.org/namespace == 'production'
  order: 100            # Thứ tự ưu tiên (số thấp = ưu tiên cao hơn)
  ingress:
  - action: Deny
    source:
      selector: app == 'frontend2'
```

*Lưu ý: Calico coi K8s NetworkPolicy chuẩn có `order: 1000`. Vì `100 < 1000`, Deny Rule sẽ chạy trước.*

**Hoặc dùng AdminNetworkPolicy (K8s 1.29+):**
- Cluster-scope (không giới hạn namespace)
- Có thể DENY tường minh
- Ưu tiên cao hơn NetworkPolicy thường

---

<!-- _class: lab -->

## 🔬 Lab Time: Demo Union Logic

Chúng ta sẽ thực hành:

1. **Setup:** Backend với default deny, tạo thêm frontend2 và db-pod.
2. **Add policies one by one:** Policy A allow frontend → backend, Policy B allow frontend2 → backend.
3. **Verify union:** Cả 2 policies cùng active đồng thời, không ai cancel ai.
4. **Demo không có DENY:** Chứng minh không thể explicit deny, và cách dùng Calico GlobalNetworkPolicy.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** BGP trong Calico — cluster là một Autonomous System, peer với ToR switch datacenter.
