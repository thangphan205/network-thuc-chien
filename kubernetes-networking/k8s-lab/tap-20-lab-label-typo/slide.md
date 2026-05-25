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

# Tập 20
## Lab 1: Bẫy "Pod thiếu label" — Connection Timeout không rõ lý do

**Phần 2 — Calico Labs** · `#lab` `#label` `#NetworkPolicy` `#debug`

---

## Mục tiêu tập này

- Debug production incident: frontend không gọi được backend mới
- Áp dụng workflow 5 bước từ Tập 19 vào thực tế
- Hiểu Felix event-driven: thêm label → rule cập nhật < 100ms
- Học checklist debug "connection timeout" trong Calico cluster

**Prerequisites:** Cluster Calico, namespace `production` có default-deny policy

---

## Tình huống thực tế

```
Thứ Hai, 9 giờ sáng. Developer gửi ticket:
"Tôi deploy backend mới. Frontend không gọi được backend.
 kubectl logs không có error. Không biết vấn đề ở đâu."

Thông tin:
- Cluster production đang chạy Calico
- Default deny đang active trong namespace
- Frontend → Backend qua Service port 8080
- curl từ frontend: timeout sau 30 giây
```

**Bạn là người xử lý — bắt đầu debug.**

---

## Root Cause (spoiler)

```
backend-v2 không có label app=backend
    ↓
NetworkPolicy podSelector: {app: backend} không match
    ↓
Felix không tạo allow rule cho backend-v2
    ↓
default-deny policy áp dụng (pod bị select vì podSelector: {})
    ↓
Frontend timeout khi kết nối
    ↓
kubectl logs không có error (problem ở network layer, không phải app)
```

**Lesson: Khi timeout không có error → nghi ngờ Network Policy ngay.**

---

## Felix Event-Driven Fix

```
Khi thêm label:

kubectl label pod backend-v2 app=backend
    ↓
K8s API nhận event → notify Felix
    ↓
Felix: "backend-v2 bây giờ match policy allow-frontend-to-backend"
    ↓
Felix atomic update iptables < 100ms
    ↓
Connection succeeded! (không cần restart Pod hay Node)
```

**Checklist debug "connection timeout":**
```bash
1. kubectl get pod --show-labels          # Labels đúng chưa?
2. kubectl get networkpolicy              # Policy nào đang active?
3. calicoctl get workloadendpoint         # Felix biết Pod không?
4. iptables -L cali-tw-<endpoint-id> -n  # Rule allow có tồn tại?
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Debug Label Typo Incident

Chúng ta sẽ thực hành:

1. **Setup incident:** Deploy backend-v2 **không có label**, frontend có đủ labels.
2. **Reproduce symptom:** Frontend timeout khi gọi backend-v2.
3. **Debug workflow:** Check Pod, check labels, check policy selectors, check Felix.
4. **Fix và verify:** Thêm label → kết nối ngay lập tức (< 100ms).

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Lab 2 — BGP không quảng bá Pod CIDR, server vật lý không ping được Pod.
