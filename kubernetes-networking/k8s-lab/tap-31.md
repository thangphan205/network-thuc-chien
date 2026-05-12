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

# Tập 31
## Cùng Node vs Khác Node: Tại sao sockops bypass hoàn toàn XDP/TC?

**Phần 3 — Cilium** · `#sockops` `#same-node` `#bypass` `#packet-flow` `#cilium`

---

## Mục tiêu tập này

- Trace packet path chi tiết: cùng node vs khác node
- Tại sao sockops không thể dùng cross-node
- Cilium detect cùng node như thế nào
- Lab đo latency để thấy sự khác biệt thực tế

---

## Same-Node Path (với sockops)

```
Pod A (10.244.1.5) → Pod B (10.244.1.8)  ← CÙNG NODE

Không có sockops:
  App A → write socket → TCP stack → veth0 →
  TC (cil_to_container) → kernel routing →
  TC (cil_from_container) → veth1 →
  TCP stack → read socket → App B
  
  Latency: ~0.3-0.5ms, CPU: 2x TCP stack

Với sockops (Cilium):
  App A → connect() ← BPF sockops intercept!
    → lookup: "is dst Pod on same node?"
    → YES → bpf_msg_redirect_map() redirect
  App A → write socket → BPF redirect → read socket → App B
  
  Latency: ~0.05ms, CPU: loopback only
```

---

## Cross-Node Path (TC path)

```
Pod A (10.244.1.5, Node1) → Pod B (10.244.2.8, Node2)

  [Node 1]                      [Node 2]
  App A
    ↓ write socket
  TCP stack
    ↓ 
  veth (Pod A side)
    ↓
  TC egress BPF (cil_to_container)
    ↓ policy check ALLOW
  kernel routing
    ↓ VXLAN/Geneve encapsulation (nếu overlay)
  eth0 (Node NIC)
    ↓ physical network
                              eth0 (Node2 NIC)
                                ↓ decapsulation
                              TC ingress BPF (cil_from_container)
                                ↓ policy check
                              veth (Pod B side)
                                ↓
                              TCP stack → App B
```

---

## sockops Detection: Làm sao biết cùng node?

```
Khi App A gọi connect(dst_ip, dst_port):
  BPF sockops program intercept syscall
  
  1. Lookup dst_ip trong cilium_lxc map:
     bpf_map_lookup_elem(&cilium_lxc, &dst_ip)
  
  2. Nếu found → dst Pod ở trên cùng node này!
     cilium_lxc chỉ chứa endpoints của NODE HIỆN TẠI
  
  3. Redirect: bpf_sock_hash_update() + bpf_msg_redirect_hash()
     → Kernel redirect write/read giữa 2 socket trực tiếp
  
  4. Nếu NOT found → cross-node traffic
     → sockops không làm gì → TC path xử lý

Key insight: cilium_lxc = "local endpoint map"
  = "danh sách Pod trên Node này"
  → Lookup miss = Pod ở node khác → TC/encap path
```

---

## Tại sao sockops KHÔNG dùng được cross-node?

```
sockops hoạt động ở socket layer:
  → Chỉ thấy: src socket ↔ dst socket (trên cùng process/kernel)
  → Không thể "redirect qua mạng vật lý"!

Cross-node cần:
  - Encapsulation (thêm outer IP header)
  - Routing (gửi đúng Node)
  - Network NIC I/O
  → Tất cả thứ này xảy ra DƯỚI socket layer

sockops → socket buffer redirect (in-kernel)
TC → packet manipulation + routing (kernel network stack)

Không thể dùng sockops cho cross-node
= Giống như không thể dùng loopback cho remote connection
```

---

## Lab Setup: 2 scenarios

```bash
multipass shell k8s-master

# Scenario 1: Same-node pods
kubectl run same-server \
  --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker1"}}' \
  -- iperf3 -s -B 0.0.0.0

kubectl run same-client \
  --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker1"}}' \
  -- sleep infinity

# Scenario 2: Cross-node pods
kubectl run cross-server \
  --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker2"}}' \
  -- iperf3 -s -B 0.0.0.0

kubectl run cross-client \
  --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker1"}}' \
  -- sleep infinity

kubectl wait --for=condition=Ready pod/same-server pod/same-client \
  pod/cross-server pod/cross-client --timeout=120s
```

---

## Lab: Đo và so sánh

```bash
SAME_IP=$(kubectl get pod same-server -o jsonpath='{.status.podIP}')
CROSS_IP=$(kubectl get pod cross-server -o jsonpath='{.status.podIP}')

# Latency test: same-node (sockops)
kubectl exec same-client -- ping -c 50 $SAME_IP | tail -2
# rtt min/avg/max = 0.048/0.062/0.089 ms

# Latency test: cross-node (TC + VXLAN)
kubectl exec cross-client -- ping -c 50 $CROSS_IP | tail -2
# rtt min/avg/max = 0.28/0.35/0.45 ms

# Bandwidth test: same-node
kubectl exec same-client -- iperf3 -c $SAME_IP -t 5
# 18.4 Gbits/sec  ← Near-loopback speed

# Bandwidth test: cross-node
kubectl exec cross-client -- iperf3 -c $CROSS_IP -t 5
# 2.1 Gbits/sec   ← Network-bound
```

---

## Lab: Verify sockops đang active

```bash
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium --field-selector spec.nodeName=k8s-worker1 \
  -o name | head -1)

# Xem sockops counter tăng khi có same-node traffic
kubectl -n kube-system exec -it $CILIUM_POD -- \
  cilium bpf metrics list | grep -i sock

# Generate some same-node traffic
kubectl exec same-client -- iperf3 -c $SAME_IP -t 3 &

# Xem counter tăng
kubectl -n kube-system exec -it $CILIUM_POD -- \
  cilium bpf metrics list | grep -i "sock\|redirect"
# Forwarded via sockops: X packets  ← Tăng!
```

---

## Key Takeaways

```
2 paths trong Cilium:

Same-node (sockops):
  App → socket → BPF intercept → redirect → socket → App
  Latency: ~0.05ms | Bandwidth: ~20 Gbps
  CPU: minimal (no TCP stack duplication)

Cross-node (TC):
  App → socket → TCP → veth → TC BPF → VXLAN → NIC
  Latency: ~0.3ms  | Bandwidth: ~2-5 Gbps (network limited)
  CPU: 2x TCP stack + encap overhead

Cilium auto-detect:
  lookup cilium_lxc map → found? → sockops
                        → not found? → TC path

Implication cho application design:
  Service calls trong cùng Node: 6-10x faster với Cilium
  → Pod topology awareness có giá trị thực!
```

> **Tập tiếp theo (Tập 32): L3/L4 Policy trong Cilium — So sánh với Kubernetes NetworkPolicy.**
