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
## iptables vs eBPF Dataplane trong Calico: O(n) vs O(1)

**Phần 2 — Calico** · `#eBPF` `#iptables` `#performance` `#dataplane` `#O(1)`

---

## Mục tiêu tập này

- Giải thích tại sao iptables không scale với số lượng Pods lớn
- Đo thời gian rule update với iptables vs eBPF
- Bật eBPF dataplane trong Calico (cần kernel 5.3+)
- Xem tc filter programs được load vào network interfaces

**Prerequisites:** Cluster Calico từ Tập 11/12. Ubuntu 26.04 có kernel 6.x — đủ điều kiện eBPF.

---

## iptables: Thiết kế tuyến tính không scale

```
1000 Pods → ~10.000 iptables rules

Packet đến:
  Check rule 1?  No
  Check rule 2?  No
  Check rule 3?  No
  ...
  Check rule 10000? Yes → ACCEPT (hoặc DROP)

Complexity: O(n) — 10x Pod = 10x thời gian check

Thêm rule mới:
  Phải LOCK toàn bộ iptables table
  Rewrite TOÀN BỘ chain (không atomic)
  → Brief window khi rules inconsistent
  → Microservices traffic có thể bị drop trong ms
```

---

## eBPF: Hash Map O(1)

```
BPF Hash Map:
  Key: {src_ip, dst_ip, dst_port, protocol}
  Value: ALLOW/DROP

Packet đến:
  Hash lookup → O(1) → ALLOW hoặc DROP
  Không phụ thuộc vào số lượng rules!

1000 Pods hay 100.000 Pods → cùng lookup time

Thêm rule mới:
  Atomic map update (single pointer swap)
  → Zero downtime, không traffic drop
  → BPF programs survive Agent restart
     (kernel giữ maps ngay cả khi Agent crash)
```

---

## So sánh iptables vs eBPF Calico

| Tiêu chí | iptables | eBPF |
| :--- | :--- | :--- |
| Lookup complexity | O(n) | **O(1)** |
| Update method | Lock + rewrite chain | **Atomic map update** |
| Traffic during update | Brief disruption | **Zero downtime** |
| Conntrack | Linux conntrack | **eBPF per-flow state** |
| Kube-proxy required | ✅ | ❌ (Calico thay thế) |
| Kernel requirement | Any | **5.3+ (Ubuntu 26.04: 6.x)** |

---

<!-- _class: lab -->

## Lab: Kiểm tra kernel version (điều kiện eBPF)

```bash
multipass shell k8s-worker1

# Ubuntu 26.04 kernel version
uname -r
# 6.x.x-xx-generic   ← eBPF fully supported!

# Kiểm tra eBPF capabilities
ls /sys/fs/bpf/
# cgroup  tc  xdp    ← BPF filesystem mounted

# Kiểm tra tc eBPF support
tc qdisc show dev eth0
# qdisc noqueue 0: root refcnt 2   ← Có thể attach eBPF program
```

---

## Lab: Bật eBPF dataplane

```bash
multipass shell k8s-master

# Tắt kube-proxy (eBPF Calico sẽ thay thế)
kubectl patch ds kube-proxy -n kube-system \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico":"true"}}}}}'

# Verify kube-proxy không còn chạy
kubectl -n kube-system get pods | grep kube-proxy
# (không có pods running)

# Bật eBPF cho Calico
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec":{"bpfEnabled":true}}'

# Verify eBPF được bật
kubectl exec -n calico-system daemonset/calico-node -c calico-node \
  -- calico-node -bpf-mode
```

---

## Lab: Xem eBPF programs được load

```bash
multipass shell k8s-worker1

# Sau khi bật eBPF, Calico load programs vào tc hooks
tc filter show dev eth0 ingress
# filter protocol all pref 1 bpf chain 0
#   filter protocol all pref 1 bpf chain 0 handle 0x1
#   calico_from_host_ep.o:[calico_from_host_ep] direct-action not_in_hw...

tc filter show dev eth0 egress
# filter protocol all pref 1 bpf chain 0
#   calico_to_host_ep.o:[calico_to_host_ep] direct-action not_in_hw...

# Xem BPF programs đang chạy
sudo bpftool prog list | grep calico
# 42: sched_cls  name calico_from_host  ...
# 43: sched_cls  name calico_to_host    ...

# Xem BPF maps (policy lookup tables)
sudo bpftool map list | grep calico
# 10: hash  name calico_policy_map  flags 0x0
```

---

## Lab: So sánh rule count iptables vs eBPF

```bash
# iptables mode: đếm rules
sudo iptables-save | wc -l
# ~200 rules cho cluster 3 nodes, 5 pods

# Với 100 pods:
# ~2000 rules → O(n) lookups

# eBPF mode: check BPF map size
sudo bpftool map dump name calico_policy_map | wc -l
# Constant size regardless of pod count!

# Thời gian apply policy update (iptables)
time kubectl apply -f big-network-policy.yaml
# real: 0.8s (bao gồm iptables lock + rewrite)

# Thời gian apply policy update (eBPF)  
time kubectl apply -f big-network-policy.yaml
# real: 0.1s (atomic BPF map update)
```

---

## Key Takeaways

**Khi nào chọn eBPF mode?**
```
✅ Production cluster, nhiều Pods (> 50)
✅ Cần low-latency policy enforcement
✅ Kernel 5.3+ (Ubuntu 26.04 luôn đủ)
✅ Muốn bỏ kube-proxy dependency

⚠️  Vẫn cần: Calico eBPF chưa thay thế hoàn toàn Cilium về features
⚠️  L7 policy: Calico eBPF không có (cần Cilium)
```

**Debug eBPF:**
```bash
tc filter show dev <interface> ingress   # eBPF programs
sudo bpftool prog list                   # Tất cả BPF programs
sudo bpftool map list                    # BPF maps (policy tables)
sudo bpftool map dump name calico_policy_map  # Policy entries
```

> **Tập tiếp theo:** Packet flow qua veth pair và conntrack — hành trình đầy đủ của 1 packet qua Calico.
