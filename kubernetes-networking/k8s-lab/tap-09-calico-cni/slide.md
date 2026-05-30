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

# Tập 9 - Calico CNI
## Cài đặt cụm Calico CNI mới hoàn toàn bằng Multipass

**Phần 2 — Calico** · `#calico` `#bootstrap` `#kubeadm` `#NetworkPolicy` `#security`
![height:200px](https://www.tigera.io/app/uploads/2026/01/Calico-logo-2026-white-text.svg)

---

## Mục tiêu tập này

- Hiểu tại sao Flannel không đủ bảo mật — bài toán **Lateral Movement** và **Blast Radius**.
- Dựng cụm K8s sạch từ đầu bằng Multipass + `kubeadm`.
- Cài **Calico CNI** qua Tigera Operator với IP Pool `10.244.0.0/16`.
- Chứng minh **NetworkPolicy được enforce thực sự** bằng Default Deny kịch bản.
- Giải phẫu chains `cali-*` trong iptables do Felix tạo ra.

---

## Vấn đề: Flannel để ngỏ toàn bộ cluster

**Lateral Movement** — attacker chiếm 1 Pod rồi di chuyển tự do sang các Pod khác:

- Flannel không enforce NetworkPolicy — mọi Pod ping được mọi Pod.
- Frontend bị chiếm → attacker quét thẳng sang Database, Payment, DNS.
- **Blast Radius = toàn bộ cluster (N-1 dịch vụ)**.

**Calico giải quyết bằng Least Privilege:**

- Felix dịch NetworkPolicy → iptables/eBPF rules ngay tại kernel mỗi Node.
- Mặc định: không có traffic nào được phép (Default Deny).
- Chỉ các kết nối được khai báo tường minh mới được đi qua.
- **Blast Radius thu hẹp tối thiểu**.

---

## Calico: 4 thành phần cốt lõi

| Thành phần | Chạy ở đâu | Vai trò |
|---|---|---|
| **Tigera Operator** | Deployment | Quản lý vòng đời toàn bộ Calico |
| **Felix** | DaemonSet (mỗi Node) | Dịch NetworkPolicy → iptables / eBPF |
| **BIRD** | DaemonSet (mỗi Node) | BGP daemon — quảng bá Pod subnet routes |
| **Typha** | Deployment (optional) | Cache K8s API cho Felix, giảm tải khi cluster lớn |

> **Felix** là trái tim: nhận event từ K8s API trong ms, update iptables atomic, không cần restart Pod hay Node.

---

## Cài Calico: 2 bước qua Tigera Operator

**Bước 1** — Deploy Tigera Operator (controller quản lý lifecycle):
```bash
kubectl create -f https://raw.githubusercontent.com/.../tigera-operator.yaml
```

**Bước 2** — Apply `Installation` CR để khai báo IP Pool:
```yaml
kind: Installation
spec:
  calicoNetwork:
    ipPools:
    - cidr: 10.244.0.0/16          # khớp với --pod-network-cidr của kubeadm
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
```

Operator đọc CR → tự deploy Felix, BIRD, Typha, cni-plugin → Nodes chuyển `Ready`.

---

## So sánh: Flannel vs Calico

| Tiêu chí | Flannel | Calico |
| :--- | :--- | :--- |
| **NetworkPolicy** | Bị bỏ qua | **Enforce tuyệt đối** |
| **Blast Radius** | Toàn cluster (N-1) | **Tối thiểu (Least Privilege)** |
| **Bảo mật mặc định** | Allow all | **Deny all qua Policy** |
| **Cơ chế** | Chuyển tiếp packet | **Chuyển tiếp + Felix Firewall** |
| **Cài đặt** | DaemonSet đơn giản | **Tigera Operator** |

---

<!-- _class: lab -->

## 🔬 Lab Time: Dựng cụm Calico & Kiểm chứng NetworkPolicy

Thực hành theo thứ tự trong `lab-guide.md`:

1. **TN1 — Dựng cụm K8s sạch:** xóa VM cũ, chạy `setup-lab.sh`, `kubeadm init`, join `worker1`/`worker2` → xác nhận `NotReady`.
2. **TN2 — Cài Calico (Tigera Operator):** apply operator + `Installation` CR, theo dõi `calico-system` Pods → nodes chuyển `Ready`.
3. **TN3 — Kiểm chứng NetworkPolicy enforce:** deploy `database`/`frontend`, test kết nối thông, apply Default Deny → kết nối bị chặn hoàn toàn.
4. **TN4 — Giải phẫu Felix iptables:** liệt kê `cali-*` chains, xem `cali-FORWARD`, đếm rules → thấy Felix dịch policy xuống kernel realtime.

👉 **Làm theo `lab-guide.md`**

---

## Key Takeaways

- **Flannel không enforce NetworkPolicy** — Felix của Calico mới là security engine thực sự.
- **Default Deny + Least Privilege** = thu hẹp Blast Radius từ toàn cluster xuống tối thiểu.
- **Tigera Operator** quản lý toàn bộ lifecycle Calico — chỉ cần khai báo `Installation` CR.
- **Felix event-driven**: Policy thay đổi → iptables update < 100ms, không restart gì cả.

> **Tập tiếp theo:** Giải phẫu kiến trúc Calico — Felix, BIRD, Typha hoạt động tương tác như thế nào?
