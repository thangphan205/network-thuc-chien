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

# Tập 20
## Lab 3: Sự cố phân quyền truy cập chéo Namespace (Logic AND vs OR)

**Phần 2 — Calico Labs** · `#lab` `#cross-namespace` `#prometheus` `#troubleshooting`

---

## Mục tiêu tập này

- Debug 2 bugs cùng lúc trong cross-namespace policy
- Hiểu cách Bug 2 (missing label) mask Bug 1 (OR vs AND)
- Chứng minh fix chỉ 1 bug có thể tạo security hole nghiêm trọng hơn
- Áp dụng checklist verification trước khi apply cross-namespace policy

**Prerequisites:** Cluster Calico, namespace `production` và `monitoring`

---

## Tình huống thực tế

```
Monitoring team báo:
"Prometheus trong namespace 'monitoring' không scrape được
 backend metrics endpoint (port 9090) trong namespace 'production'.
 Chúng tôi đã viết NetworkPolicy rồi nhưng vẫn timeout."

Thông tin:
- Namespace monitoring (label?)
- Prometheus Pod label: role=prometheus
- Backend Pod label: app=backend
- Policy đã apply nhưng không hoạt động
```

**Lab này: 2 bugs cùng lúc — phải fix cả 2 mới OK.**

---

<!-- _class: warn -->

## 2 Bugs cùng lúc — Nguy hiểm đặc biệt

```
Bug 1: OR thay vì AND (dấu "-" sai chỗ)
  → Policy quá rộng: bất kỳ Pod nào trong monitoring vào được
  → Security hole!

Bug 2: Namespace thiếu label
  → namespaceSelector không match → policy không hoạt động
  → Bug 2 mask Bug 1 (timeout → người dùng không thấy security hole)

Nếu chỉ fix Bug 2 (thêm label namespace):
  → Bug 1 trở thành security hole THỰC SỰ
  → Policy hoạt động nhưng quá rộng
  → Bất kỳ Pod nào trong monitoring đều vào được!
```

**Phải debug và fix CẢ HAI.**

---

## Logic Cú Pháp NetworkPolicy: AND vs OR

*Sự khác biệt cực kỳ nhỏ ở cú pháp dấu gạch ngang (`-`) tạo nên hậu quả bảo mật khổng lồ:*

### ❌ Cấu hình sai (OR Logic) - 2 dấu gạch ngang
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels: {name: monitoring}
  - podSelector:
      matchLabels: {role: prometheus}
```
> **Kết quả:** Cho phép *bất kỳ Pod nào* thuộc namespace `monitoring` **HOẶC** *bất kỳ Pod nào* có nhãn `role: prometheus` ở bất kỳ đâu trong cluster (bao gồm cả namespace `default`, `dev`...).

---

## Logic Cú Pháp NetworkPolicy: AND vs OR (tiếp)

###  Cấu hình đúng (AND Logic) - 1 dấu gạch ngang duy nhất
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels: {name: monitoring}
    podSelector:                  # <- Không có dấu "-" ở đây = AND!
      matchLabels: {role: prometheus}
```
> **Kết quả:** Chỉ cho phép Pod có nhãn `role: prometheus` **VÀ** phải nằm trong namespace `monitoring`. Đây là quy tắc bảo mật chặt chẽ nhất theo nguyên tắc đặc quyền tối thiểu.

---

<!-- _class: lab -->

## Pro Tip: Kubernetes Namespace Auto-Labeling

- Từ **Kubernetes v1.21+**, control plane tự động gắn nhãn mặc định `kubernetes.io/metadata.name: <namespace-name>` cho mọi Namespace khi khởi tạo.
- **Lợi ích:** Ta không còn lo quên gắn nhãn thủ công (tránh được hoàn toàn Bug 2).

### Cấu hình Modern & An Toàn:
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: monitoring  # Nhãn tự động của K8s
    podSelector:
      matchLabels:
        role: prometheus
```
*(Khuyên dùng cho các dự án thực tế để loại bỏ thao tác thủ công dễ sai sót).*

---

## Checklist trước khi apply cross-namespace policy

```bash
# 1. Verify namespace có label
kubectl get namespace <ns> --show-labels
# Expected: name=<ns> trong LABELS column

# 2. Đếm dấu "-" trong from block
# Mỗi "- " = 1 item = OR với items khác
# Cùng item = AND

# 3. Test với rogue pod (namespace đúng, label sai)
kubectl run rogue -n monitoring --image=nicolaka/netshoot -- sleep infinity
kubectl -n monitoring exec rogue -- nc -zv <backend-ip> 9090
# Expected: timeout (blocked)

# 4. Test với legit pod (namespace đúng, label đúng)
kubectl -n monitoring exec prometheus -- nc -zv <backend-ip> 9090
# Expected: success
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Debug 2 Bugs Cùng Lúc

Chúng ta sẽ thực hành:

1. **Setup incident:** Deploy NetworkPolicy chéo namespace (cấu hình lỗi chéo namespace).
2. **Reproduce:** Xác minh Prometheus bị chặn kết nối (Connection Timeout) tới Backend.
3. **Thử thách 30 phút tự giải:** Học viên tự tìm nguyên nhân và khắc phục lỗi logic ẩn.
4. **Hướng dẫn gỡ lỗi chuẩn:** Đối chiếu các bước troubleshooting chuẩn để tìm ra 2 lỗi ẩn.
5. **Fix và verify:** Áp dụng logic AND chính xác, dán nhãn namespace và kiểm tra ma trận kết nối bảo mật.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Tập 21 — Lab 4: Network Policy Nâng Cao với Calico
