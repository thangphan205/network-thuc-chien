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

# Tập 11
## Migrate từ Flannel sang Calico — NetworkPolicy thật sự được enforce

**Phần 2 — Calico** · `#calico` `#migrate` `#NetworkPolicy` `#lateral-movement`

---

## Mục tiêu tập này

- Hiểu kỹ thuật lateral movement và tính toán blast radius
- Migrate cluster từ Flannel sang Calico (Tigera Operator)
- Verify NetworkPolicy bây giờ được enforce thực sự
- Kiểm tra Calico iptables chains Felix tạo ra

**Prerequisites:** Cluster từ Tập 10 với Flannel (chuẩn bị migrate sang Calico)

---

## Lateral Movement: Từ 1 Pod → Toàn cluster

```
Kịch bản thực tế:

Bước 1: Frontend Pod có Log4Shell vulnerability
         → Attacker chạy code từ xa trong frontend

Bước 2: Từ frontend, attacker scan:
         nmap 10.244.0.0/16 -p 3306,5432,6379,27017,8080,9200
         → Tìm thấy: database (3306), redis (6379), elasticsearch (9200)

Bước 3: Tấn công Database
         mysql -h 10.244.2.10 -u root -p''
         → Dump toàn bộ user data

Bước 4: Pivoting — từ Database sang service khác
         Dùng credentials trong DB tấn công payment service

Tổng thiệt hại: Toàn bộ cluster, mọi service, mọi data
```

---

## Blast Radius: Đo lường định lượng

```
Blast Radius = Số service có thể bị tấn công
               từ 1 Pod bị compromise

Flannel (không policy):
  Blast Radius = N-1  (N = tổng số services)
  50 services → Blast Radius = 49  (gần 100%)

Calico + Default Deny + Least Privilege:
  Frontend policy: chỉ gọi được backend:8080 và DNS:53
  Blast Radius = 2  (chỉ backend và DNS)
```

**Nguyên tắc Least Privilege trong K8s:**
```
Mỗi Pod chỉ giao tiếp với ĐÚNG service nó cần
Không hơn, không kém — Default Deny cho phần còn lại
```

---

## Calico — CNI có NetworkPolicy enforcement thật sự

```
Calico gồm 3 thành phần chính:

┌─────────────────────────────────────────┐
│  Tigera Operator (quản lý lifecycle)    │
└──────────────────┬──────────────────────┘
                   │
         ┌─────────┼─────────┐
         │         │         │
    ┌────▼───┐ ┌───▼──┐ ┌────▼────┐
    │ Felix  │ │ BIRD │ │  Typha  │
    │ Policy │ │  BGP │ │  Cache  │
    │→iptables│ │ daemon│ │(cluster)│
    └────────┘ └──────┘ └─────────┘

Felix chạy trên MỖI Node:
  NetworkPolicy → iptables/eBPF rules
  Enforce TRƯỚC khi packet đi vào Pod
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Migrate Flannel → Calico và Verify

Chúng ta sẽ thực hành:

1. **Cleanup Flannel:** Xóa Flannel DaemonSet và network interfaces.
2. **Cài Calico:** Dùng Tigera Operator và Installation CR.
3. **Verify NetworkPolicy:** Deploy lại services, apply Default Deny, chứng minh Calico enforce.
4. **Kiểm tra iptables:** Xem chains `cali-FORWARD`, `cali-fw-*` Felix tạo.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## So sánh trước/sau migrate

| | Flannel | Calico |
| :--- | :--- | :--- |
| NetworkPolicy | Bị bỏ qua | **Được enforce** |
| Blast Radius (1 Pod bị chiếm) | **Toàn cluster** | Chỉ services được allow |
| Default posture | Allow all | **Deny all (sau khi apply policy)** |
| iptables rules | Chỉ kube-proxy | **kube-proxy + Felix** |
| Cài đặt | DaemonSet đơn giản | **Tigera Operator** |

> **Tập tiếp theo:** Giải phẫu kiến trúc Calico — Felix, BIRD, Typha làm gì chính xác?
