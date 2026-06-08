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

# Tập 22
## Tổng kết & Workflow Troubleshooting Calico chuẩn

**Phần 2 — Calico** · `#troubleshooting` `#debug` `#methodology` `#calicoctl`

---

## Mục tiêu tập này

- Hệ thống hóa workflow debug Calico (không đoán mò) sau 4 bài Lab thực hành
- Đúc kết đủ bộ tool: calicoctl, ip route, iptables-save, tcpdump
- Tổng kết 4 sự cố mạng kinh điển: Label Typo, BGP Route Loss, WireGuard MTU Black Hole, Cross-Namespace Policy
- Phân biệt rạch ròi lúc nào check Control Plane vs Data Plane

**Prerequisites:** Đã hoàn thành 4 bài Lab thực hành từ Tập 18 đến Tập 21

---

## Workflow debug Calico — 5 bước chuẩn

```
Symptom: Pod A không kết nối được tới Pod B (Timeout/Refused)

Bước 1: CHECK BASICS
  kubectl get pods -o wide       # Pod đang chạy? Đúng Node?
  kubectl get endpoints          # Service có endpoints chưa?

Bước 2: CHECK ROUTING & BGP
  calicoctl node status          # BGP sessions UP/Established?
  ip route show proto bird       # Có route đến subnet của Pod B?

Bước 3: CHECK NETWORK POLICY
  kubectl get networkpolicy      # Có policy nào select Pod không?
  calicoctl get workloadep       # Felix đã nhận diện Pod endpoint?

Bước 4: CHECK LABELS & LOGIC
  kubectl get pod --show-labels  # Nhãn Pod có khớp selector (AND/OR)?

Bước 5: CHECK KERNEL DATA PATH & LOGS
  iptables-save | grep cali      # Rule có tồn tại trong iptables?
  tcpdump -i any host <pod-ip>   # Gói tin có thực sự đi đến card mạng?
```

---

## Control Plane vs Data Plane

```
Control Plane (Quản lý & Thiết lập):
  calicoctl node status       → BGP session state (BIRD)
  calicoctl get workloadep    → Felix Agent biết Pod không?
  kubectl get networkpolicy   → Policy cấu hình trong K8s API

Data Plane (Thực thi & Chuyển mạch):
  ip route show               → Route có nạp vào Linux Kernel?
  iptables -L cali-FORWARD    → Rule có trong Linux iptables/eBPF?
  conntrack -L | grep <ip>    → Bảng theo dõi trạng thái kết nối
  tcpdump -i any host <ip>    → Gói tin thực tế đi/đến đâu?

Bẫy kinh điển:
"BGP UP" ≠ "Routing OK" (Lab 2 - Tập 19)
"Policy applied" ≠ "iptables rule match" (Lab 1 - Tập 18, Lab 3 - Tập 20)
→ Phải kiểm tra song song cả hai tầng!
```

---

## Debug Command Toolkit Cheatsheet

```bash
# Control plane
calicoctl node status                        # BGP sessions
calicoctl get workloadendpoint               # Workload endpoints Felix nhận diện
calicoctl get networkpolicy --all-namespaces # Tất cả policies trong Calico

# Data plane
ip route show proto bird                     # Pod subnet routes học qua BGP
iptables-save | grep cali | wc -l            # Số lượng Calico rules trong Node
iptables -L cali-tw-<iface-id> -n            # Xem rule inbound vào Pod (tw = to-workload)
iptables -L cali-fw-<iface-id> -n            # Xem rule outbound từ Pod (fw = from-workload)
conntrack -L -p tcp | grep <pod-ip>          # Trạng thái connection

# Packet trace (TEMP, xóa sau khi debug)
iptables -I FORWARD 1 -j LOG --log-prefix "DBG: "
dmesg -w | grep DBG
```

---

<!-- _class: lab -->

## 🔬 Tổng hợp 4 Lab Scenarios đã thực hành

Chúng ta đã gỡ lỗi thành công 4 sự cố thực tế kinh điển:

1. **Lab 1 (Tập 18): Label Typo** -> Felix Event-Driven cập nhật iptables cực nhanh, timeout do drop âm thầm khi thiếu nhãn.
2. **Lab 2 (Tập 19): BGP Route Loss** -> BGP session giữa các Node UP nhưng máy chủ ngoài cluster không có route tĩnh/động để forward packet.
3. **Lab 3 (Tập 20): Cross-Namespace Policy** -> Lỗi cú pháp dấu gạch ngang (AND vs OR logic) bị che giấu bởi lỗi thiếu nhãn Namespace (Bug Masking).
4. **Lab 4 (Tập 21): Network Policy Nâng Cao** -> Hạn chế namespace-level policy bằng cách áp dụng GlobalNetworkPolicy bảo vệ IMDS toàn cụm và Egress control sử dụng NetworkSet.

---

## ✅ Lời khuyên khi Troubleshoot mạng K8s

1. **Không đoán mò:** Luôn bám sát workflow 5 bước từ cơ bản đến nâng cao.
2. **Lỗi im lặng (Timeout) vs Lỗi từ chối (Refused):**
   - Timeout -> Packet bị DROP âm thầm (thường do NetworkPolicy/iptables).
   - Connection Refused -> Packet đến được đích nhưng không có app nào lắng nghe port (TCP RST).
3. **Luôn kiểm tra ma trận bảo mật:** Khi sửa NetworkPolicy, hãy chắc chắn kiểm tra cả client được phép (legit) và client trái phép (rogue/attacker).

---

> **Tập tiếp theo:** Tập 23 — Calico Observability: Giám sát mạng K8s với Prometheus & Grafana
