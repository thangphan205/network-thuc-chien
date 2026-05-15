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

# Tập 3
## Services & kube-proxy: ClusterIP, NodePort, LoadBalancer từ góc nhìn packet

**Phần 0 — Nền tảng K8s Networking** · `#kube-proxy` `#iptables` `#IPVS` `#services`

---

## Mục tiêu tập này

- Giải thích tại sao ClusterIP không `ping` được nhưng `curl` được
- Trace packet qua iptables chains của kube-proxy
- So sánh iptables mode vs IPVS mode vs nftables mode (K8s v1.33+)
- Dùng `conntrack` xem trạng thái connection sau DNAT

**Prerequisites:** Cluster từ Tập 1, pods từ Tập 2 đang chạy

---

## ClusterIP: Virtual IP không có interface

```bash
kubectl get svc kubernetes
# NAME         TYPE        CLUSTER-IP   PORT(S)   AGE
# kubernetes   ClusterIP   10.96.0.1    443/TCP   1h
```

**`10.96.0.1` không tồn tại ở đâu:**
```bash
# Thử ping
ping 10.96.0.1     → timeout (ICMP không được NAT)

# Thử curl
curl https://10.96.0.1:443  → response! (TCP được kube-proxy xử lý)
```

**Tại sao?** kube-proxy dùng iptables `DNAT` để rewrite destination IP.
ICMP không qua conntrack → không DNAT → timeout.
TCP qua conntrack → DNAT thành công → kết nối được.

---

## Kiến trúc kube-proxy iptables mode

```
Packet đến ClusterIP 10.96.X.X:PORT
    │
    ▼ iptables nat PREROUTING
KUBE-SERVICES
    │
    ├── match 10.96.X.X → KUBE-SVC-XXXXXXXXXXXXXXXX
    │                           │
    │              ┌────────────┼────────────┐
    │              ▼            ▼            ▼
    │        KUBE-SEP-AAA  KUBE-SEP-BBB  KUBE-SEP-CCC
    │         (Pod 1 IP)   (Pod 2 IP)    (Pod 3 IP)
    │           DNAT          DNAT          DNAT
    │
    └── match !local → KUBE-NODEPORTS (NodePort traffic)
```

**Thuật toán chọn endpoint:** `statistic mode random probability 0.33` — round-robin ngẫu nhiên.

---

## 3 loại Service: ClusterIP, NodePort, LoadBalancer

| Loại | Scope | Cơ chế | Dùng khi |
| :--- | :--- | :--- | :--- |
| **ClusterIP** | Trong cluster | iptables DNAT | Internal service |
| **NodePort** | Mọi Node IP:Port | iptables + DNAT | Dev/test expose |
| **LoadBalancer** | External LB IP | Cloud LB controller | Production |
| **Headless** | DNS → Pod IPs | Không VIP | StatefulSet, direct |

**externalTrafficPolicy: Local vs Cluster:**
```
Cluster (default): traffic đến bất kỳ Node nào → kube-proxy forward đến Pod bất kỳ
                   → 1 hop thêm, src IP bị SNAT (mất IP client gốc)

Local: traffic đến Node có Pod → forward thẳng
       → không thêm hop, giữ src IP client thật
       → nhưng Node không có Pod → traffic bị drop
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Khám phá Kube-Proxy & Services

Chúng ta sẽ thực hành các bước sau trong phần Lab:

1. **Quan sát ClusterIP Service:** Phân tích tại sao ClusterIP chỉ hoạt động với giao thức TCP/UDP mà không thể `ping` được.
2. **Theo dõi dấu vết iptables:** Lần theo đường đi của gói tin từ chuỗi `KUBE-SERVICES` đến các rules DNAT do kube-proxy tạo ra.
3. **Phân tích Connection Tracking:** Dùng `conntrack` để quan sát trạng thái của kết nối sau khi đã thực hiện DNAT.
4. **Kiểm thử NodePort Service:** Phân tích cách Traffic được định tuyến khi truy cập NodePort từ bên ngoài Cluster.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

**kube-proxy iptables mode:**
```
ClusterIP → KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-YYY → DNAT → Pod IP
```

**3 điểm quan trọng:**
1. ClusterIP không `ping` được vì ICMP không qua DNAT
2. kube-proxy viết iptables rules khi Service/Endpoint thay đổi
3. `conntrack -L` thấy mapping VIP → Pod IP sau DNAT

**Debug commands:**
```bash
iptables -t nat -L KUBE-SERVICES -n      # Tất cả services
iptables -t nat -L KUBE-SVC-XXXX -n     # Endpoint selection
iptables -t nat -L KUBE-SEP-XXXX -n     # DNAT rule
conntrack -L | grep <service-ip>         # Active connections
```

> **Tập tiếp theo:** DNS trong K8s — tại sao mỗi request tốn 5 DNS query?
