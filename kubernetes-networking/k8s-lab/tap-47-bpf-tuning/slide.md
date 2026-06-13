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
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 47
## BPF Map Sizing + Resource Tuning — Production Capacity Planning

**Phần 3 — Cilium** · `#bpf` `#tuning` `#capacity` `#maps` `#production`

---

## BPF Maps: Kernel Memory, Fixed Size

```
Bình thường (userspace apps):
  "Hết memory? Mua thêm RAM, allocate thêm."
  Dynamic: malloc, GC, resize at runtime

BPF Maps (kernel):
  Fixed size khi load BPF program
  Cannot resize without reload
  Full = DROP (không phải "slow", không phải "OOM")
  
Tại sao fixed?
  Kernel maps phải lock-free, O(1) access
  Variable-size = complexity = bugs = kernel panic
  Safety > flexibility

Consequence:
  Cluster nhỏ → default sizes đủ dùng nhiều năm
  Cluster lớn → có thể hit limit trong vài tháng
  Không monitor → đột ngột mất network, không hiểu tại sao
```

---

## BPF Map Types: Defaults và Công dụng

| Map | Default Size | Full = ? |
| :--- | :--- | :--- |
| `bpf-ct-global-tcp-max` | 524,288 | New TCP conn dropped |
| `bpf-ct-global-any-max` | 262,144 | New UDP/ICMP dropped |
| `bpf-nat-global-max` | 524,288 | SNAT fail, conn dropped |
| `bpf-lb-map-max` | 65,536 | New Service not configured |
| `bpf-policy-map-max` | 16,384 | New policy rule not enforced |

```
Conntrack (CT): mỗi active TCP connection = 1 entry
  Default 524,288: OK cho cluster ~1000 pods, ~500 req/s
  High-traffic cluster (10k req/s, short connections): đầy sau vài giờ

LB map: mỗi Service backend = 1 entry
  Default 65,536: OK cho ~5,000 Services (10 backends each)
  
Policy map: per-endpoint, mỗi policy rule select pod này = 1 entry
  Default 16,384: hit limit với complex NetworkPolicy setups
```

---

## Sizing Formulas

```
Conntrack TCP:
  CT_TCP_MAX = peak_new_conn_per_sec × avg_conn_duration_sec × 2
  
  ×2: inbound connections + outbound connections
  
  Example: 1,000 req/s, avg 30s connections
  CT_TCP_MAX = 1,000 × 30 × 2 = 60,000   (default 524,288: safe)
  
  Example: 10,000 req/s, avg 60s connections  
  CT_TCP_MAX = 10,000 × 60 × 2 = 1,200,000  (⚠️ vượt default!)

NAT:
  NAT_MAX = CT_TCP_MAX (same order of magnitude)

LB:
  LB_MAX = total_backends × 2 (backend + reverse lookup)
  
  500 Services × 10 backends = 5,000 backend entries
  5,000 × 2 = 10,000   (default 65,536: safe)

Safety margin: size ×2 từ calculated value
```

---

## Signs of BPF Map Exhaustion

```
Triệu chứng:
  Pods đột ngột mất connection đến service
  Hubble drop reasons:
    CT_ALLOCATION_FAILED       → conntrack map full
    MAP_LB_BACKEND_SLOT_NO_MATCH → LB map full
    POLICY_DENIED (new, unexplained) → policy map full
  
  kubectl describe pod: "no network" nhưng pod Running
  New pods: network works (existing BPF programs ok)
  Existing connections: drop suddenly (CT entry expired)

Monitoring alert (PrometheusRule):
  cilium_bpf_map_ops_total{op="update",outcome="fail"} > 0
  
  Cụ thể hơn:
  rate(cilium_bpf_map_ops_total{outcome="fail"}[5m]) > 0
  → Alert: "BPF map full on node X"
  
  Thêm capacity metric (nếu Cilium expose):
  cilium_bpf_ct_tcp_count / bpf_ct_global_tcp_max > 0.8
  → Alert: "Conntrack 80% full — resize soon"
```

---

## Tune: Helm Values

```bash
# Inspect current config
kubectl -n kube-system exec -it $CILIUM_POD -- \
  cilium config | grep -E "ct|nat|lb|policy" | grep "max"

# Calculate needs → update values
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set bpf.ctTcpMax=1048576 \      # 2× default (524288)
  --set bpf.ctAnyMax=524288 \       # 2× default
  --set bpf.natMax=2097152 \        # 4× default (high SNAT cluster)
  --set bpf.lbMapMax=131072 \       # 2× default (many Services)
  --set bpf.policyMapMax=32768      # 2× default (many policies)

# What happens during upgrade:
#   cilium-agent restart (rolling, per node)
#   BPF programs reloaded with new map sizes
#   Existing connections: brief interruption per node (~2-5s)
#   New connections: immediately use new sizes

# Verify after upgrade:
kubectl -n kube-system exec -it $CILIUM_POD -- \
  cilium config | grep bpf-ct-global-tcp-max
# Expected: 1048576
```

---

## Capacity Planning Workflow

```
Production workflow (before cluster go-live):
  
  1. Estimate traffic profile:
     peak_rps: forecast from load testing
     avg_conn_duration: measure from application
     
  2. Calculate (Python script in lab):
     CT_TCP = peak_rps × duration × 2 × safety_factor(2)
     NAT = CT_TCP
     
  3. Set values BEFORE production traffic:
     helm upgrade --set bpf.ctTcpMax=<calculated>
     
  4. Alert at 80% usage:
     PrometheusRule: map_ops_fail > 0 → PagerDuty
     
  5. Regular review:
     Monthly: check cilium_bpf_ct_tcp_count trend
     Before new feature rollout: re-estimate

Scale event checklist:
  +1000 pods → recalculate policy map per-node
  New microservice (high-req) → recalculate CT/NAT
  More Services → recalculate LB map
```

---

<!-- _class: lab -->

## 🔬 Lab Time: BPF Tuning

1. **Inspect** BPF map sizes: `bpftool map list`, `cilium config`
2. **Measure** current conntrack usage vs max
3. **Calculator** Python script: input peak_rps + duration → sizes
4. **Stress test** policy map: 100 NetworkPolicies, watch Hubble drops
5. **Tune** `helm upgrade --set bpf.ctTcpMax=1048576`
6. **Alert** PrometheusRule cho `map_ops_total{outcome="fail"}`

👉 **Xem chi tiết trong `lab-guide.md`**

> **Khoá học hoàn thành!** 47 tập — Flannel → Calico → Cilium production 🎓
