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

# Tập 16
## Cross-namespace Policy: AND vs OR — Dấu gạch "-" quan trọng thế nào!

**Phần 2 — Calico** · `#NetworkPolicy` `#cross-namespace` `#AND` `#OR` `#YAML`

---

## Mục tiêu tập này

- Phân biệt rõ AND vs OR logic trong NetworkPolicy YAML
- Demo sự khác biệt bằng cách kiểm tra traffic thực tế
- Viết cross-namespace policy đúng cho Prometheus scraping
- Hiểu tại sao namespace phải có label

**Prerequisites:** Cluster Calico, namespace `production` và `monitoring` với Pods

---

## Bài toán: Prometheus scrape backend metrics

```
Namespace: monitoring
  Pod: prometheus (label: role=prometheus)

Namespace: production
  Pod: backend (label: app=backend)
  Port: 9090 (metrics endpoint)

Goal: Chỉ cho phép prometheus trong namespace monitoring
      scrape backend metrics (port 9090)
      KHÔNG cho phép prometheus nào khác scrape
```

**Yêu cầu:** Cả 2 điều kiện phải đúng đồng thời:
1. Phải là Pod có label `role: prometheus`
2. Phải ở trong namespace `monitoring`

---

<!-- _class: warn -->

## OR logic (Bug thường gặp)

```yaml
ingress:
- from:
  - namespaceSelector:          # Điều kiện A
      matchLabels:
        name: monitoring
  - podSelector:                # ← Có dấu "-" → ITEM MỚI → OR
      matchLabels:
        role: prometheus
```

**Kết quả thực tế (WRONG):**
```
Rogue pod trong monitoring              → ✅ (match A — bất kỳ Pod trong monitoring!)
Prometheus (monitoring namespace)       → ✅ (match A)
Prometheus (other namespace)            → ❌ (Luật B chỉ tìm Pod in local 'production' namespace!)
```
*(Lưu ý: Luật B `- podSelector` không có `namespaceSelector` đi kèm chỉ tìm Pod `role: prometheus` chạy nội bộ trong chính namespace `production` chứ không tìm được các namespace khác. Rogue pod lọt vào hoàn toàn là do kẽ hở của Luật A mở toang toàn bộ namespace `monitoring`!)*

**Policy quá rộng — không an toàn!**

---

## AND logic (Đúng)

```yaml
ingress:
- from:
  - namespaceSelector:          # Điều kiện A
      matchLabels:
        name: monitoring
    podSelector:                # ← KHÔNG có dấu "-" → CÙNG ITEM → AND
      matchLabels:
        role: prometheus
```

**Kết quả (CORRECT):**
```
Prometheus (monitoring namespace, role=prometheus)  → ✅ (A AND B)
Prometheus (other namespace, role=prometheus)       → ❌ (B đúng nhưng A sai)
Random pod (monitoring namespace, no role)          → ❌ (A đúng nhưng B sai)
```

---

## Quy tắc YAML nhớ mãi

```yaml
# OR: mỗi điều kiện là một list item (có dấu -)
from:
- namespaceSelector: ...   # Item 1
- podSelector: ...         # Item 2 (OR với Item 1)

# AND: cùng một list item
from:
- namespaceSelector: ...   # Cùng item
  podSelector: ...         # AND với namespaceSelector trên
```

**Visual:**
```
OR  → nhiều dấu "-" → nhiều items → ANY ONE must match
AND → một dấu "-"  → một item    → ALL must match within item
```

**Namespace phải có label:**
```bash
kubectl label namespace monitoring name=monitoring
# Nếu không label → namespaceSelector không match được!
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Demo AND vs OR và hậu quả

Chúng ta sẽ thực hành:

1. **Deploy môi trường:** production/backend, monitoring/prometheus, monitoring/rogue.
2. **Apply OR policy (buggy):** Chứng minh rogue pod vào được backend.
3. **Fix thành AND:** Chứng minh rogue bị chặn, prometheus vẫn qua.
4. **Verify namespace labels:** Tại sao namespace phải có label.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Union Logic — nhiều NetworkPolicy cùng chọn 1 Pod thì cộng hưởng như thế nào?
