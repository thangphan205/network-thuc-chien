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

# Tập 10
## Giới hạn của Flannel: Tại sao không có NetworkPolicy?

**Phần 1 — Flannel** · `#flannel` `#security` `#NetworkPolicy` `#lateral-movement`

---

## Mục tiêu tập này

- Demo lateral movement trong cluster dùng Flannel
- Giải thích tại sao NetworkPolicy resource bị **chấp nhận nhưng không có tác dụng**
- Đo blast radius khi 1 Pod bị compromise
- Hiểu khi nào Flannel phù hợp và khi nào không

**Prerequisites:** Cluster từ Tập 6-9 với Flannel đang chạy (VXLAN hoặc host-gw đều được)

---

<!-- _class: warn -->

## Flannel: Security hole by design

```
Cluster Flannel — mọi Pod "thấy" nhau không giới hạn:

frontend     (10.244.1.5)  ──────────────► database    (10.244.2.10)
hacker-pod   (10.244.1.9)  ──────────────► database    (10.244.2.10) ✅
hacker-pod   (10.244.1.9)  ──────────────► payment-api (10.244.3.5)  ✅
hacker-pod   (10.244.1.9)  ──────────────► redis       (10.244.2.20) ✅
hacker-pod   (10.244.1.9)  ──────────────► internal-api(10.244.3.8)  ✅

Không có gì ngăn cản!
```

**Lý do Flannel không có NetworkPolicy:**
- Flannel là CNI "minimal" — chỉ giải quyết connectivity, không làm security
- NetworkPolicy enforcement cần cài iptables/eBPF rules tại mỗi Node
- Flannel không cài hooks đó → không thể enforce được
- **Nếu apply NetworkPolicy resource → K8s chấp nhận, nhưng Flannel bỏ qua hoàn toàn**

---

<!-- _class: warn -->

## Nguy hiểm thầm lặng: NetworkPolicy bị bỏ qua

```bash
# Người dùng nghĩ rằng mình đang được bảo vệ...
kubectl apply -f deny-all-networkpolicy.yaml

kubectl get networkpolicy
# NAME       POD-SELECTOR   AGE
# deny-all   <none> (All)   5s  ← K8s chấp nhận resource!

# ...nhưng thực ra Flannel không enforce gì cả
kubectl exec hacker-pod -- curl http://database:5432
# ← Vẫn kết nối được! NetworkPolicy hoàn toàn vô hiệu.
```

> **Đây là nguy hiểm lớn nhất:** Người vận hành tưởng mình đang được bảo vệ bởi NetworkPolicy nhưng thực ra cluster hoàn toàn mở. Không có cảnh báo, không có error.

---

<!-- _class: lab -->

## 🔬 Lab Time: Lateral Movement & NetworkPolicy vô hiệu

Chúng ta sẽ thực hành:

1. **Setup mục tiêu:** Deploy pod giả lập database và payment-api.
2. **Demo lateral movement:** Từ một "compromised pod", scan và kết nối tất cả targets.
3. **Apply NetworkPolicy:** Chứng minh nó không có tác dụng với Flannel bằng iptables inspection.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Blast Radius so sánh

| Scenario | Blast radius khi 1 Pod bị chiếm |
| :--- | :--- |
| **Flannel (không policy)** | **Toàn bộ cluster** — mọi service, mọi database |
| **Calico + Default Deny** | Chỉ services policy cho phép |
| **Cilium + L7 Policy** | Chỉ HTTP endpoints cụ thể |

```
Cluster Flannel 50 microservices:
1 Pod bị compromise → hacker reach được 49 services còn lại

Calico cluster Default Deny:
1 Pod bị compromise → hacker chỉ reach được 2-3 services
```

---

## Khi nào dùng Flannel?

**Phù hợp:**
```
✅ Dev/local lab (bài này!)
✅ Learning Kubernetes networking
✅ Cluster internal, không expose internet
✅ Prototype — cần nhanh, không cần security
```

**Không phù hợp:**
```
❌ Production với nhiều team
❌ Cluster chứa sensitive data (DB, payment, PII)
❌ Compliance: PCI-DSS, HIPAA, SOC2
❌ Multi-tenant cluster
```

> **Phần tiếp theo (Tập 11):** Calico — CNI có NetworkPolicy enforcement thật sự. Cùng L3 routing, thêm iptables/eBPF security hooks.
