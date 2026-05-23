# Cilium CLI Troubleshooting Cheatsheet
> Cilium v1.19 | Kubernetes v1.36 | Ubuntu 26.04 | ARM64

---

## 1. Quick Health Check

```bash
# Tổng quan cluster health
cilium status

# Verbose với tất cả components
cilium status --verbose

# Chờ cho đến khi healthy
cilium status --wait

# Health check giữa các nodes
cilium connectivity test --test health
```

**Những gì cần kiểm tra:**
```
Cilium:        OK        ← agent healthy
Operator:      OK        ← operator healthy
Hubble Relay:  OK        ← observability ready
Cluster health: 3/3      ← tất cả nodes reachable
Controller Status: X/X   ← tất cả controllers healthy
```

---

## 2. Node & Agent Debugging

```bash
# Xem cilium pods trên từng node
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

# Exec vào cilium agent trên node cụ thể
NODE="worker1"
CILIUM_POD=$(kubectl get pods -n kube-system -o wide \
  | grep cilium | grep $NODE \
  | grep -v envoy | grep -v operator \
  | awk '{print $1}')
kubectl -n kube-system exec -it $CILIUM_POD -- cilium-dbg status

# Xem logs của agent
kubectl -n kube-system logs $CILIUM_POD --tail=100
kubectl -n kube-system logs $CILIUM_POD --since=5m | grep -i error

# Xem agent config đang chạy
kubectl -n kube-system exec -it $CILIUM_POD -- cilium-dbg config

# Xem toàn bộ debuginfo
kubectl -n kube-system exec -it $CILIUM_POD -- cilium-dbg debuginfo
```

---

## 3. Endpoint Debugging

```bash
# List tất cả endpoints
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg endpoint list

# Output:
# ENDPOINT   POLICY (ingress/egress)   IDENTITY   LABELS   IPv4   STATUS
# 1234       Enabled/Enabled           12345      ...      ...    ready

# Get chi tiết một endpoint
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg endpoint get <ENDPOINT_ID>

# Xem policy đang apply trên endpoint
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg endpoint get <ENDPOINT_ID> | grep -A20 "policy"

# Regenerate endpoint (khi policy stuck)
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg endpoint config <ENDPOINT_ID> debug=true

# Xem endpoint theo pod name
kubectl get ciliumendpoints -A
kubectl get ciliumendpoints -n default <pod-name> -o yaml
```

---

## 4. Policy Debugging

```bash
# List tất cả policies
kubectl get networkpolicy -A
kubectl get ciliumnetworkpolicy -A
kubectl get ciliumclusterwidenetworkpolicy

# Xem policy details
kubectl describe networkpolicy <name> -n <namespace>
kubectl describe ciliumnetworkpolicy <name> -n <namespace>

# Xem resolved policy trên endpoint
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg policy get

# Trace policy decision cho một flow cụ thể
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg policy trace \
  --src-k8s-pod default/client \
  --dst-k8s-pod default/webserver \
  --dport 80

# Xem identity của pod
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg identity get <IDENTITY_ID>

# List tất cả identities
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg identity list
```

---

## 5. Hubble - Flow Observability

```bash
# Start port-forward (chạy trước)
cilium hubble port-forward &

# Kiểm tra Hubble status
hubble status

# Xem tất cả flows realtime
hubble observe --follow

# Filter theo namespace
hubble observe --namespace default --follow

# Chỉ xem DROPPED flows - quan trọng nhất khi debug policy
hubble observe --verdict DROPPED --follow

# Xem flows của một pod
hubble observe --pod default/client --follow

# Xem flows giữa 2 pods
hubble observe \
  --from-pod default/client \
  --to-pod default/webserver \
  --follow

# Filter theo protocol
hubble observe --protocol DNS --follow
hubble observe --protocol HTTP --follow
hubble observe --protocol TCP --follow

# Xem flows trong 1 phút qua
hubble observe --since 1m

# Output dạng JSON để parse
hubble observe --output json --follow | jq '.flow.verdict'

# Top flows theo namespace
hubble observe --namespace default \
  --output json \
  | jq -r '.flow | "\(.source.namespace)/\(.source.pod_name) -> \(.destination.namespace)/\(.destination.pod_name)"' \
  | sort | uniq -c | sort -rn | head -10
```

---

## 6. eBPF Maps Debugging

```bash
# Xem LB table (Services & Backends)
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf lb list

# Tìm service theo ClusterIP
CLUSTER_IP=$(kubectl get svc <service-name> -o jsonpath='{.spec.clusterIP}')
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg bpf lb list | grep $CLUSTER_IP

# Xem NAT table
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf nat list

# Xem conntrack table
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf ct list global

# Xem endpoint map
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf endpoint list

# Xem policy map của endpoint
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg bpf policy get <ENDPOINT_ID>

# Xem tunnel map (VXLAN endpoints)
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf tunnel list

# Trực tiếp trên node với bpftool
sudo bpftool prog list | grep sched_cls
sudo bpftool map list | grep cilium
sudo bpftool map dump name cilium_lb4_serv
```

---

## 7. Network Connectivity Debugging

```bash
# Full connectivity test
cilium connectivity test

# Chỉ test health
cilium connectivity test --test health

# Test specific scenario
cilium connectivity test --test pod-to-pod
cilium connectivity test --test pod-to-service
cilium connectivity test --test node-to-node

# Ping giữa nodes qua Cilium
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg ping <NODE_IP>

# Xem cluster nodes
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg node list

# Check IPAM
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg bpf ipmasq list
```

---

## 8. Service & Load Balancing Debugging

```bash
# Xem tất cả services trong eBPF
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg service list

# Get chi tiết một service
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg service get <SERVICE_ID>

# Xem LB algorithm
kubectl -n kube-system get configmap cilium-config -o yaml \
  | grep -E "lb-algorithm|maglev"

# Đổi LB algorithm
cilium config set bpf-lb-algorithm maglev   # consistent hashing
cilium config set bpf-lb-algorithm random   # random (default)
kubectl -n kube-system rollout restart daemonset/cilium
```

---

## 9. Metrics & Monitoring

```bash
# Xem tất cả metrics
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg metrics list

# Metrics quan trọng nhất cần monitor
curl -s http://<NODE_IP>:9962/metrics | grep -E \
  "cilium_drop_count_total|
   cilium_policy_verdict_total|
   cilium_endpoint_state|
   cilium_bpf_map_pressure|
   cilium_controllers_failing|
   cilium_agent_bootstrap"

# Prometheus queries hay dùng
# Drop rate
rate(cilium_drop_count_total[5m])

# Policy verdicts
rate(cilium_policy_verdict_total[5m])

# Endpoints không ready
cilium_endpoint_state{endpoint_state!="ready"}

# BPF map pressure
cilium_bpf_map_pressure > 0.8

# Agent restart count
changes(cilium_agent_bootstrap_seconds_count[1h])
```

---

## 10. Troubleshooting Decision Tree

```
Pod không connect được?
│
├─► hubble observe --verdict DROPPED --follow
│   │
│   ├─► Thấy "Policy denied" ?
│   │   └─► NetworkPolicy issue
│   │       kubectl get networkpolicy -A
│   │       kubectl describe networkpolicy <name>
│   │       cilium-dbg policy trace --src... --dst...
│   │
│   ├─► Thấy "Policy denied by denylist" ?
│   │   └─► Explicit deny rule đang block
│   │       kubectl get ciliumnetworkpolicy -A
│   │
│   └─► Không thấy gì?
│       └─► Không phải policy issue
│           ├─► DNS failure?
│           │   hubble observe --protocol DNS
│           │   → Thấy DNS DROPPED? Thiếu egress UDP 53 rule
│           │
│           └─► Network issue?
│               cilium connectivity test
│               cilium-dbg node list
│               cilium-dbg bpf tunnel list
│
Service không hoạt động?
│
├─► kubectl get svc <name>         ← ClusterIP đúng không?
├─► cilium-dbg bpf lb list         ← Backends có trong eBPF map không?
├─► cilium-dbg service list        ← Service được register không?
└─► hubble observe --to-service    ← Traffic có reach service không?
│
Cilium agent unhealthy?
│
├─► kubectl -n kube-system logs ds/cilium --since=5m
├─► cilium-dbg status
├─► cilium-dbg controller list     ← Controllers nào đang fail?
└─► cilium connectivity test --test health
```

---

## 11. Common Issues & Fixes

| Triệu chứng | Nguyên nhân | Fix |
|-------------|-------------|-----|
| curl timeout, DNS OK | L4 NetworkPolicy block | `hubble --verdict DROPPED` → fix policy |
| curl timeout, DNS fail | Egress policy thiếu UDP 53 | Thêm egress rule cho kube-system:53 |
| 403 từ Envoy | L7 CiliumNetworkPolicy block | Check `ciliumnetworkpolicy` |
| Pod stuck `waiting-for-identity` | Cilium agent issue | Restart cilium pod trên node đó |
| Service traffic skewed | LB algorithm | Switch sang `maglev` |
| High drop rate sau deploy | NetworkPolicy mới | `hubble --verdict DROPPED` tìm policy |
| Cilium agent restart loop | Config sai | Check logs, rollback config |
| BPF map pressure cao | Quá nhiều endpoints/services | Scale down hoặc tăng map size |

---

## 12. Essential One-liners

```bash
# Health check nhanh
cilium status | grep -E "OK|error|warning"

# Tìm pod đang bị drop traffic
hubble observe --verdict DROPPED --follow --output json \
  | jq -r '.flow.source.pod_name' | sort | uniq -c | sort -rn

# Xem tất cả identities của một namespace
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg identity list | grep "namespace=default"

# Check kube-proxy đã bị replace chưa
kubectl -n kube-system get pods | grep kube-proxy
# (không có output = đã bị replace bởi Cilium)

# Verify BPF masquerading
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg status | grep Masquerad

# Xem node connectivity matrix
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg status | grep "Cluster health"

# Force endpoint regeneration
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg endpoint regenerate <ENDPOINT_ID>

# Dump toàn bộ state để gửi cho support
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg sysdump > cilium-sysdump.zip
```
