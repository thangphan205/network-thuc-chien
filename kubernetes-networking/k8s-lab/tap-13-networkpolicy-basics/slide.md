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

# Tập 13
## NetworkPolicy cơ bản: Default Deny và Ingress Policy

**Phần 2 — Calico** · `#NetworkPolicy` `#default-deny` `#ingress` `#least-privilege`

---

## Mục tiêu tập này

- Viết `default-deny` policy cho toàn namespace
- Viết ingress policy cho phép traffic cụ thể
- Test từng bước: trước policy, sau deny, sau allow
- Hiểu tại sao phải allow DNS traffic riêng

**Prerequisites:** Cluster Calico từ Tập 9, không có NetworkPolicy nào đang active

---

## Bước 1: Default Allow (không có policy)

```
Khi không có NetworkPolicy nào trong namespace:
→ K8s cho phép TẤT CẢ traffic (default allow)

frontend → backend    ✅
attacker → backend    ✅ (không ai chặn)
```

**Nguyên tắc K8s NetworkPolicy:**
> "Chỉ khi có ít nhất 1 NetworkPolicy SELECT một Pod,
>  thì traffic đến/đi Pod đó mới bị restrict.
>  Pod không bị select bởi policy nào = không bị restrict gì."

---

## Bước 2: Default Deny Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}       # {} = select ALL pods trong namespace
  policyTypes:
  - Ingress             # Không có ingress rules = deny ALL ingress
  # Không liệt kê Egress = egress vẫn được phép
```

**Kết quả:**
```
frontend → backend    ❌ (ingress đến backend bị deny)
backend → database    ✅ (egress từ backend vẫn OK)
external → frontend   ❌ (ingress đến frontend bị deny)
```

---

## Bước 3: Allow cụ thể

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend            # Policy áp dụng cho Pod backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend       # Chỉ cho phép từ Pod frontend
    ports:
    - protocol: TCP
      port: 8080              # Chỉ port 8080
```

---

## Lỗi phổ biến: Quên allow DNS!

```bash
# Sau khi apply default-deny-egress:
kubectl exec backend -- curl http://service-name
# curl: (6) Could not resolve host: service-name
# Tại sao? DNS query đến CoreDNS cũng bị chặn!
```

```yaml
# Fix: Allow egress DNS (PHẢI LÀM TRƯỚC KHI DENY EGRESS)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

---

## Thứ tự triển khai policy đúng

```
1. Allow DNS egress (LUÔN LÀM ĐẦU TIÊN!)
2. Allow egress cần thiết (HTTP, database...)
3. Apply default deny ingress
4. Allow ingress cụ thể
5. Apply default deny egress
```

**Test matrix sau mỗi bước:**
```bash
for src in frontend backend; do
  for dst_port in "backend-svc 8080"; do
    kubectl -n production exec $src -- nc -zv $dst_port 2>&1 | tail -1
  done
done
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Test từng bước

Chúng ta sẽ thực hành:

1. **Deploy namespace `production`:** frontend, backend, backend-svc.
2. **Test baseline:** Tất cả pass khi không có policy.
3. **Apply default deny ingress:** Verify backend bị chặn.
4. **Apply allow rule:** Verify frontend được vào, others bị chặn.
5. **Demo DNS break:** Apply default deny egress → DNS fail → Fix với allow-dns.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Cross-namespace Policy — AND vs OR, sai 1 dấu gạch là sai policy!
