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

# Tập 9
## host-gw Mode: Khi nào bỏ encapsulation để tăng tốc?

**Phần 1 — Flannel** · `#host-gw` `#routing` `#performance` `#L2` `#no-encap`

---

## Mục tiêu tập này

- So sánh VXLAN vs host-gw về latency và throughput
- Hiểu điều kiện bắt buộc để dùng host-gw (cùng L2 segment)
- Switch Flannel từ VXLAN sang host-gw trực tiếp
- Đo throughput bằng `iperf3` để so sánh hai mode

**Prerequisites:** Cluster từ Tập 6-8 với Flannel VXLAN đang chạy

---

## host-gw: Routing thay vì Encapsulation

**VXLAN mode:**
```
Pod A → cni0 → flannel.1 → [UDP wrap] → eth0 → [UDP unwrap] → flannel.1 → cni0 → Pod B
        CPU: encode   ←────── overhead ─────→ CPU: decode
```

**host-gw mode:**
```
Pod A → cni0 → eth0 → [direct routing] → eth0 → cni0 → Pod B
                No encoding, no decoding — MTU đầy đủ 1500 bytes
```

**Cách hoạt động:**
```
Node 1 routing table (thêm bởi flanneld):
10.244.2.0/24 via 192.168.64.12 dev eth0  ← "10.244.2.x thì qua Node 2"
10.244.0.0/24 via 192.168.64.10 dev eth0  ← "10.244.0.x thì qua Master"

Không cần tunnel! Router/switch phải forward được Pod CIDRs.
```

---

## Điều kiện bắt buộc cho host-gw

```
Yêu cầu: Tất cả Nodes phải cùng L2 segment

✅ OK: On-premise cluster, tất cả Nodes cùng switch
  Node1 (192.168.1.10) ──┐
  Node2 (192.168.1.11) ──┤── L2 Switch ── Router
  Node3 (192.168.1.12) ──┘
  → Packet từ Node1 đến Node2 chỉ qua switch (L2 forward)

❌ FAIL: Cloud VMs, Nodes ở nhiều subnet/AZ khác nhau
  Node1 (10.0.1.10 / us-east-1a) ── Router ── Node2 (10.0.2.10 / us-east-1b)
  → Router không biết route đến 10.244.x.x
  → Packet bị DROP tại router

❌ FAIL: Nodes qua nhiều hop router (datacenter khác nhau)
```

**Multipass lab:** Tất cả VMs ở cùng network `192.168.64.0/24` → host-gw hoạt động!

---

<!-- _class: lab -->

## Lab: Switch sang host-gw mode

```bash
multipass shell k8s-master

# Xem config hiện tại (VXLAN)
kubectl -n kube-flannel get configmap kube-flannel-cfg -o jsonpath='{.data.net-conf\.json}'
# {"Network": "10.244.0.0/16", "Backend": {"Type": "vxlan"}}

# Edit ConfigMap để chuyển sang host-gw
kubectl -n kube-flannel edit configmap kube-flannel-cfg
# Thay:  "Backend": {"Type": "vxlan"}
# Thành: "Backend": {"Type": "host-gw"}

# Restart flanneld để apply config mới
kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds
kubectl -n kube-flannel rollout status daemonset kube-flannel-ds
```

---

## Lab: Quan sát sự thay đổi

```bash
# Sau khi restart, quan sát trên worker1
multipass shell k8s-worker1

# Interface flannel.1 BIẾN MẤT (không cần VTEP nữa)
ip link show | grep flannel
# (không có output) ← flannel.1 đã bị xóa!

# Routing table thay đổi hoàn toàn
ip route show | grep 10.244
# 10.244.0.0/24 via 192.168.64.10 dev eth0   ← Route đến master (direct!)
# 10.244.1.0/24 dev cni0                     ← Local subnet
# 10.244.2.0/24 via 192.168.64.12 dev eth0   ← Route đến worker2 (direct!)

# MTU của cni0 = 1500 (không còn overhead VXLAN)
ip link show cni0
# cni0: mtu 1500   ← Tăng từ 1450!
```

---

## Lab: Benchmark VXLAN vs host-gw

```bash
# Cài iperf3 trong cluster
kubectl run iperf3-server --image=networkstatic/iperf3 -- iperf3 -s
kubectl expose pod iperf3-server --port=5201

IPERF_SVC=$(kubectl get svc iperf3-server -o jsonpath='{.spec.clusterIP}')

# Test throughput (cross-node)
kubectl run iperf3-client --image=networkstatic/iperf3 \
  --overrides='{"spec":{"nodeName":"k8s-worker2"}}' -- \
  iperf3 -c $IPERF_SVC -t 30 -P 4

# VXLAN mode kết quả (từ Tập 8):
# [SUM] 0-30s  12.5 Gbits/sec  (approx, depends on VM)

# host-gw mode kết quả (hiện tại):
# [SUM] 0-30s  14.2 Gbits/sec  ← ~10-15% tăng throughput

# Test latency (ping RTT)
kubectl exec iperf3-client -- ping -c 100 $IPERF_SVC | tail -3
# VXLAN: rtt min/avg/max = 0.45/0.62/0.95 ms
# host-gw: rtt min/avg/max = 0.28/0.38/0.55 ms  ← ~35% giảm latency
```

---

## Lab: Xem tcpdump — không còn UDP port 8472

```bash
# Bắt traffic cross-node — không còn VXLAN
sudo tcpdump -i eth0 -n udp port 8472

# Thay vào đó sẽ thấy ICMP thẳng (outer = inner, không có VXLAN)
sudo tcpdump -i eth0 -n icmp
# 12:35:00 IP 10.244.1.5 > 10.244.2.7: ICMP echo request
# ← Packet gốc, không wrapped trong UDP!
```

---

## So sánh tổng kết VXLAN vs host-gw

| Tiêu chí | VXLAN | host-gw |
| :--- | :--- | :--- |
| Encapsulation overhead | 50 bytes | **0 bytes** |
| MTU cho payload | 1450 bytes | **1500 bytes** |
| Điều kiện | Bất kỳ topology | **Phải cùng L2** |
| CPU overhead | Encode/decode | **Không** |
| Latency (p99) | ~0.6 ms | **~0.4 ms** |
| Cloud compatibility | ✅ | ❌ (thường) |
| Dùng khi | Cloud, multi-subnet | **On-prem, same rack** |

> **Tập tiếp theo:** Giới hạn lớn nhất của Flannel — tại sao không có NetworkPolicy và tại sao đó là vấn đề nghiêm trọng trong production.
