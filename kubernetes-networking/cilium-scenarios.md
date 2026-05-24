# Cilium Troubleshooting Scenarios
> Cilium v1.19 | Kubernetes v1.36 | Ubuntu 26.04 | ARM64

---

## Scenario 1: NetworkPolicy L4 — Ingress Block

### Background
Khi bất kỳ NetworkPolicy nào select một Pod, Cilium chuyển Pod đó sang **default-deny mode** — mọi traffic không được explicitly allow sẽ bị drop. Đây là lỗi phổ biến nhất khi mới bắt đầu dùng NetworkPolicy.

### Symptom
- `curl` đến Service trả về `000` hoặc timeout
- Pod khác trong cùng namespace cũng không connect được
- Xảy ra ngay sau khi apply một NetworkPolicy mới

### Key Concepts
- `podSelector: {}` — select **tất cả** Pods trong namespace
- Cilium enforce policy tại eBPF hook trên `lxcXXXX` interface
- Verdict `DROPPED` trong Hubble = bị block bởi policy

### Diagnosis Steps

```bash
# Bước 1: Xác nhận traffic đang bị drop
hubble observe --namespace default --verdict DROPPED --follow

# Bước 2: Xem policies đang apply
kubectl get networkpolicy -n default

# Bước 3: Xem policy nào select pod nào
kubectl describe networkpolicy <name> -n default

# Bước 4: Kiểm tra labels của pods
kubectl get pods --show-labels -n default
```

### Expected Hubble Output (broken state)
```
default/client (ID:1102) <> default/webserver:80 (ID:44733) policy-verdict:none TRAFFIC_DIRECTION_UNKNOWN DENIED (TCP Flags: SYN)
default/client (ID:1102) <> default/webserver:80 (ID:44733) Policy denied DROPPED (TCP Flags: SYN)
```

### Root Cause
`deny-all-ingress` policy với `podSelector: {}` applies to all pods. Không có rule nào allow traffic từ `client`.

### Fix
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-webserver
  namespace: default
spec:
  podSelector:
    matchLabels:
      run: webserver        # apply policy cho webserver pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          run: client       # allow từ client pod
    ports:
    - port: 80
```

### Verification
```bash
# Hubble không còn DROPPED flows
hubble observe --namespace default --verdict DROPPED --follow

# curl trả về 200
kubectl exec client -- curl -s -o /dev/null -w "%{http_code}\n" http://webserver-svc
```

### Key Lesson
> Khi có NetworkPolicy select một Pod, tất cả traffic không được allow đều bị DROP.  
> `kubectl run` tự động gán label `run: <name>` — dùng label đó trong podSelector.  
> **Luôn dùng `hubble observe --verdict DROPPED` là bước đầu tiên khi debug connectivity.**

---

## Scenario 2: Cross-Namespace NetworkPolicy

### Background
NetworkPolicy có thể restrict traffic giữa các namespaces bằng `namespaceSelector`. Lỗi thường gặp là dùng sai field để chỉ định namespace name.

### Symptom
- Pod trong namespace A không curl được Service trong namespace B
- Pod trong cùng namespace B cũng bị block (nếu có deny-all)
- Hubble hiện `Policy denied DROPPED`

### Key Concepts
- `namespaceSelector` dùng **labels** của namespace, không phải tên trực tiếp
- Kubernetes tự động gán label `kubernetes.io/metadata.name=<name>` cho mọi namespace
- Kết hợp `namespaceSelector` + `podSelector` trong cùng một `from` entry = AND condition

### Diagnosis Steps
```bash
# Bước 1: Xem dropped flows với source namespace
hubble observe --namespace backend --verdict DROPPED --follow

# Bước 2: Kiểm tra labels của namespace
kubectl get namespace default --show-labels

# Bước 3: Xem policy đang apply
kubectl describe networkpolicy -n backend
```

### Common Mistakes

| Cách viết | Kết quả |
|-----------|---------|
| `namespaceSelector: { namespace: default }` | ❌ Invalid field |
| `namespaceSelector: { matchLabels: { name: default } }` | ❌ Label không tồn tại |
| `namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: default } }` | ✅ Correct |

### Fix
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-default
  namespace: backend
spec:
  podSelector:
    matchLabels:
      run: api-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: default  # label tự động của namespace
    ports:
    - port: 80
```

### Verification
```bash
# Từ namespace default — phải 200
kubectl exec client -- curl -s -o /dev/null -w "%{http_code}\n" \
  http://api-svc.backend.svc.cluster.local

# Từ namespace khác — phải bị block
kubectl run attacker --image=curlimages/curl --restart=Never -n backend -- sleep 3600
kubectl exec -n backend attacker -- curl -s -o /dev/null -w "%{http_code}\n" \
  --max-time 3 http://api-svc.backend.svc.cluster.local
# Expected: timeout
```

### Key Lesson
> Namespace selector dùng labels, không phải name.  
> Kubernetes auto-label: `kubernetes.io/metadata.name=<namespace-name>`  
> Verify bằng: `kubectl get namespace <name> --show-labels`

---

## Scenario 3: DNS Resolution Failure (Egress Policy)

### Background
Đây là lỗi **phổ biến nhất** khi viết Egress NetworkPolicy. Khi apply Egress policy mà không include rule cho DNS, pod không resolve được hostname — nhưng curl bằng IP trực tiếp vẫn hoạt động.

### Symptom
- `curl http://service-name` → `000` (timeout, exit code 28)
- `curl http://<pod-ip>` → `200` (works)
- Chỉ xảy ra với pods có Egress NetworkPolicy

### Key Concepts
- DNS resolution dùng **UDP port 53** đến CoreDNS trong namespace `kube-system`
- Egress policy block **mọi outbound traffic** không được explicitly allow
- DNS failure xảy ra **trước khi** TCP connection được establish

### Diagnosis Steps
```bash
# Bước 1: Test để confirm DNS failure pattern
kubectl exec <pod> -- curl -s --max-time 3 http://service-name
# → 000 (timeout)

kubectl exec <pod> -- curl -s --max-time 3 http://<pod-ip>
# → 200 (works)

# Bước 2: Xem Hubble — DNS bị drop
hubble observe --pod default/<pod> --follow
# → dns-test -> coredns:53 Policy denied DROPPED (UDP)

# Bước 3: Xem egress policy hiện tại
kubectl get networkpolicy -n default
kubectl describe networkpolicy <name>
```

### Expected Hubble Output (broken state)
```
default/dns-test:58352 (ID:61049) <> kube-system/coredns:53 (ID:5054) policy-verdict:none TRAFFIC_DIRECTION_UNKNOWN DENIED (UDP)
default/dns-test:58352 (ID:61049) <> kube-system/coredns:53 (ID:5054) Policy denied DROPPED (UDP)
```

### Fix
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-with-dns
  namespace: default
spec:
  podSelector:
    matchLabels:
      run: my-app
  policyTypes:
  - Egress
  egress:
  # Rule 1: Allow application traffic
  - to:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - port: 8080

  # Rule 2: ALWAYS include DNS — bắt buộc phải có
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP   # DNS over TCP cho responses lớn
```

### Verification
```bash
# Hubble hiện DNS ALLOWED
hubble observe --pod default/dns-test --follow
# → dns-test -> coredns:53 ALLOWED (UDP)
# → dns-test -> webserver:80 FORWARDED

# curl bằng service name thành công
kubectl exec dns-test -- curl -s -o /dev/null -w "%{http_code}\n" http://webserver-svc
# → 200
```

### Key Lesson
> **Production Rule #1:** Mọi Egress policy PHẢI có DNS rule (UDP 53 → kube-system).  
> Không có DNS rule → hostname resolution fail → service unreachable.  
> Pattern nhận dạng: service name timeout + IP direct works = DNS policy issue.

---

## Scenario 4: Node-to-Pod Connectivity & Host Network Bypass

### Background
NetworkPolicy **không apply** cho traffic từ host network namespace. kubelet health probes, node-level monitoring agents, và CNI health checks đều bypass NetworkPolicy hoàn toàn.

### Symptom
- Apply deny-all policy nhưng Pod vẫn `Ready 1/1`
- kubelet probe vẫn PASS dù không có allow rule
- Dễ gây hiểu nhầm: nghĩ policy không hoạt động

### Key Concepts
- Cilium enforce policy trên **Pod-to-Pod** và **external-to-Pod** traffic
- Traffic từ `(host)` network namespace không bị restrict bởi NetworkPolicy
- kubelet chạy trên host → probe traffic luôn FORWARDED

### Diagnosis Steps
```bash
# Xem probe traffic trong Hubble
hubble observe --pod default/probe-test --follow

# Bạn sẽ thấy:
# 10.x.x.x (host) -> default/probe-test:80  to-endpoint FORWARDED
# ^^^^^^^^^^^
# "(host)" = từ host network namespace → bypass NetworkPolicy
```

### Expected Hubble Output
```
10.0.1.161:43436 (host) -> default/probe-test:80 (ID:4017) to-endpoint FORWARDED (TCP Flags: SYN)
10.0.1.161:43436 (host) <- default/probe-test:80 (ID:4017) to-stack FORWARDED (TCP Flags: SYN, ACK)
```

### What NetworkPolicy DOES and DOES NOT block

| Traffic type | Blocked by NetworkPolicy? |
|---|---|
| Pod → Pod (same namespace) | ✅ Yes |
| Pod → Pod (cross namespace) | ✅ Yes |
| External → Pod | ✅ Yes (Ingress) |
| Pod → External | ✅ Yes (Egress) |
| kubelet → Pod (health probe) | ❌ No (host network) |
| Cilium health checks | ❌ No (host network) |
| Node-level agents (Prometheus, Datadog) | ❌ No (if using hostNetwork: true) |

### Key Lesson
> `(host)` trong Hubble = traffic từ host namespace = bypass NetworkPolicy.  
> kubelet probes luôn hoạt động dù có deny-all policy.  
> Nếu muốn restrict node-level access → cần Host Firewall (Cilium feature riêng).

---

## Scenario 5: CiliumNetworkPolicy — L7 HTTP Policy

### Background
Standard Kubernetes NetworkPolicy chỉ hoạt động ở L3/L4 (IP, port, protocol). `CiliumNetworkPolicy` mở rộng sang L7 — có thể enforce HTTP method, path, headers, gRPC methods, và Kafka topics. Traffic bị block ở L7 nhận HTTP error response thay vì timeout.

### Symptom (after policy applied)
- `GET /` → `200 OK` ✅
- `GET /admin` → `403 Forbidden` ❌ (với header `server: envoy`)
- `POST /` → `403 Forbidden` ❌ (với header `server: envoy`)

### Key Concepts
- L7 policy traffic đi qua **Envoy proxy** (cilium-envoy DaemonSet)
- Envoy trả về proper HTTP error codes, không drop packet
- `server: envoy` header = indicator L7 policy đang enforce
- L4 block = timeout/000; L7 block = 403/405 từ Envoy

### Policy Structure
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-policy
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: api              # apply cho endpoint nào
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: http-client    # allow từ endpoint nào
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"     # chỉ allow GET
          path: "^/$"       # chỉ allow path / (exact match với regex)
```

### Diagnosis Steps
```bash
# Bước 1: Kiểm tra CiliumNetworkPolicy đã apply chưa
kubectl get ciliumnetworkpolicy -n default
# Cột VALID phải là True

# Bước 2: Verify labels match
kubectl get pods --show-labels

# Bước 3: Test và xem response headers
kubectl exec http-client -- curl -v http://api-svc/admin 2>&1 | grep "^<"
# < HTTP/1.1 403 Forbidden
# < server: envoy    ← confirm L7 enforcement
```

### L4 vs L7 Block Comparison

| Scenario | HTTP Code | Server Header | curl Exit Code |
|----------|-----------|---------------|----------------|
| No policy | 200 | nginx | 0 |
| L4 NetworkPolicy block | — | — | 28 (timeout) |
| L7 wrong path | 403 | envoy | 0 |
| L7 wrong method | 403 | envoy | 0 |
| L7 allowed | 200 | nginx | 0 |

### Path Matching
```yaml
# Exact path only
- method: "GET"
  path: "^/$"          # hanya /

# Allow path prefix
- method: "GET"
  path: "^/api/.*"     # /api/anything

# Allow multiple paths
- method: "GET"
  path: "^/health$"
- method: "GET"
  path: "^/metrics$"
```

### Key Lesson
> L7 policy dùng `CiliumNetworkPolicy` (cilium.io/v2), không phải standard `NetworkPolicy`.  
> `server: envoy` trong response header = L7 policy đang active.  
> `403` từ Envoy ≠ application 403 — là Cilium policy enforcement.  
> Regex trong `path` — dùng `^/$` cho exact match, `^/api/.*` cho prefix.

---

## Scenario 6: Cilium Agent Restart & eBPF Persistence

### Background
Một trong những điểm mạnh nhất của Cilium là **zero-downtime** khi agent restart. eBPF programs và maps được load vào kernel — chúng persist ngay cả khi cilium agent process bị kill. Existing connections không bị drop.

### Symptom (there is no symptom — this is verification)
- cilium pod bị delete → DaemonSet tạo pod mới trong ~21 giây
- Existing connections survive trong suốt quá trình restart
- eBPF programs vẫn enforce policy ngay cả khi agent đang down

### Key Concepts
- eBPF programs sống trong **kernel memory**, không phải trong cilium process
- Khi agent restart, nó **reconcile** lại state từ Kubernetes API vào eBPF maps
- Không có "flush and reload" như iptables

### Verification Steps
```bash
# Bước 1: Xem eBPF programs đang chạy trên node (không phụ thuộc vào agent)
# Login vào worker1
sudo bpftool prog list | grep sched_cls | head -20
# → Hàng chục programs với tên: cil_from_container, cil_lxc_policy, cil_to_overlay, ...

# Bước 2: Xem eBPF maps
sudo bpftool map list | grep cilium | head -20
# → cilium_lb4_serv, cilium_lb4_back, cilium_snat_v4_, cilium_policyst, ...

# Bước 3: Delete cilium pod và observe
kubectl delete pod -n kube-system <cilium-pod-on-worker1>

# Bước 4: Verify connectivity không bị gián đoạn
kubectl exec client -- curl -s -o /dev/null -w "%{http_code}\n" http://webserver-svc
# → 200 (ngay cả trong lúc agent restart)

# Bước 5: Agent tự recover
kubectl get pods -n kube-system | grep cilium
# → Pod mới được tạo trong ~21 giây
```

### eBPF Map Inspection
```bash
# Xem NAT table (human-readable)
CILIUM_POD=$(kubectl get pods -n kube-system -o wide | grep cilium | grep worker1 | grep -v envoy | grep -v operator | awk '{print $1}')
kubectl -n kube-system exec -it $CILIUM_POD -- cilium-dbg bpf nat list | head -20

# Output giải thích:
# TCP OUT 192.168.x.x:44338 -> 192.168.x.x:6443  Created=15804sec ago
#                                                  ^^^^^^^^^^^^^^^^^^^
#                                                  Connection đã tồn tại 4+ giờ → survive agent restart
```

### eBPF Program Reference

| Program name | Role |
|---|---|
| `cil_from_container` | Xử lý packet rời khỏi pod (egress) |
| `cil_lxc_policy` | Enforce NetworkPolicy ingress |
| `cil_lxc_policy_egress` | Enforce NetworkPolicy egress |
| `cil_to_overlay` | Gửi packet vào VXLAN tunnel |
| `cil_from_overlay` | Nhận packet từ VXLAN tunnel |
| `tail_handle_ipv4` | IPv4 routing |
| `tail_nodeport_*` | NodePort service handling |

### Key Lesson
> eBPF programs + maps persist trong kernel — agent restart không gây downtime.  
> `sudo bpftool prog list` và `sudo bpftool map list` để verify eBPF state trực tiếp.  
> Đây là lý do Cilium HA tốt hơn iptables-based CNI khi agent crash.

---

## Scenario 7: Service Load Balancing Debug

### Background
Cilium implement Service load balancing hoàn toàn bằng eBPF, thay thế kube-proxy. Service translation xảy ra tại **socket level** — trước khi packet rời khỏi pod. eBPF LB table có thể được inspect trực tiếp để debug distribution issues.

### Symptom
- Traffic không distribute đều giữa các backends
- Một số backends nhận quá nhiều requests, số khác nhận quá ít
- Service không reachable sau khi scale deployment

### Key Concepts
- Cilium dùng **random** hoặc **Maglev consistent hashing** cho LB
- Service backends được store trong eBPF map `cilium_lb4_serv`
- SOCK_XLATE: ClusterIP → PodIP translation xảy ra tại syscall `connect()`
- Maglev distribution đều hơn khi có nhiều source IPs

### Diagnosis Steps
```bash
# Bước 1: Lấy ClusterIP của service
CLUSTER_IP=$(kubectl get svc backend-svc -o jsonpath='{.spec.clusterIP}')
echo "ClusterIP: $CLUSTER_IP"

# Bước 2: Xem eBPF LB table — verify backends registered
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg bpf lb list | grep "$CLUSTER_IP:80"

# Expected output:
# 10.x.x.x:80/TCP (1)   10.0.1.x:5678/TCP (23) (1)   ← backend slot 1
# 10.x.x.x:80/TCP (2)   10.0.2.x:5678/TCP (23) (2)   ← backend slot 2
# 10.x.x.x:80/TCP (3)   10.0.2.x:5678/TCP (23) (3)   ← backend slot 3

# Bước 3: Verify backends match pods
kubectl get pods -l app=backend -o wide

# Bước 4: Measure distribution
for i in $(seq 1 100); do
  kubectl exec lb-client -- curl -s http://backend-svc/
done | sort | uniq -c | sort -rn
```

### LB Algorithm Comparison

| Algorithm | Behavior | Use case |
|-----------|----------|----------|
| `random` | Random selection, O(1) | Default, most workloads |
| `maglev` | Consistent hashing | Session affinity, multiple source IPs |

```bash
# Switch LB algorithm
cilium config set bpf-lb-algorithm maglev
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium

# Verify algorithm changed (lookup table size increases)
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg bpf lb list | grep "$CLUSTER_IP:80"
# random:  backend slot (23)
# maglev:  backend slot (36)  ← larger consistent hash table
```

### SOCK_XLATE Observation
```bash
# Hubble hiện socket-level translation
hubble observe --pod default/client --follow
# default/client (ID:1102) <> default/backend-svc:80 (world) SOCK_XLATE_POINT_UNKNOWN TRACED (TCP)
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# ClusterIP được translate sang PodIP TRƯỚC khi packet gửi đi
```

### Key Lesson
> `cilium-dbg bpf lb list` = xem Service backends đang register trong eBPF kernel map.  
> Missing backend = pod chưa được registered (check pod labels match service selector).  
> SOCK_XLATE trong Hubble = socket-level LB — packet không bao giờ có ClusterIP.  
> Maglev tốt hơn random khi có nhiều source clients cần consistent routing.

---

## Scenario 8: Metrics & Monitoring

### Background
Cilium expose metrics qua Prometheus endpoint port `9962` (agent) và `9963` (operator). Kết hợp với Hubble metrics, đây là nền tảng cho production observability.

### Key Metrics

| Metric | Alert threshold | Meaning |
|--------|----------------|---------|
| `cilium_drop_count_total{reason="Policy denied"}` | > 100/s for 2m | Possible policy misconfiguration |
| `cilium_endpoint_state{endpoint_state="waiting-for-identity"}` | > 0 for 2m | Endpoint stuck, check agent |
| `up{job="cilium-agent-metrics"}` | == 0 for 1m | Agent unreachable |
| `cilium_bpf_map_pressure` | > 0.85 | eBPF map near full |
| `cilium_controllers_failing_total` | > 0 | Internal controller failure |
| `changes(cilium_agent_bootstrap_seconds_count[1h])` | > 3 | Agent restarting frequently |

### Setup Steps
```bash
# 1. Enable metrics port
cilium config set prometheus-serve-addr ':9962'
kubectl -n kube-system rollout restart daemonset/cilium

# 2. Create metrics Service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: cilium-agent-metrics
  namespace: kube-system
  labels:
    k8s-app: cilium
spec:
  selector:
    k8s-app: cilium
  ports:
  - name: prometheus
    port: 9962
    targetPort: 9962
  clusterIP: None
EOF

# 3. Create ServiceMonitor
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cilium-agent
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      k8s-app: cilium
  endpoints:
  - port: prometheus
    interval: 30s
    path: /metrics
EOF
```

### Essential Prometheus Queries
```promql
# Drop rate by reason
rate(cilium_drop_count_total[5m])

# Policy verdict distribution
rate(cilium_policy_verdict_total[5m])

# Endpoints not ready
cilium_endpoint_state{endpoint_state!="ready"}

# BPF map pressure over 80%
cilium_bpf_map_pressure > 0.8

# Agent restarts in last hour
changes(cilium_agent_bootstrap_seconds_count[1h])

# Drop rate specifically from policy denial
rate(cilium_drop_count_total{reason="Policy denied"}[5m])
```

### PrometheusRule Alerts
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cilium-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: cilium.rules
    rules:
    - alert: CiliumHighDropRate
      expr: rate(cilium_drop_count_total{reason="Policy denied"}[5m]) > 100
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "High drop rate on {{ $labels.instance }}"
        description: "Possible misconfigured NetworkPolicy — check Hubble"

    - alert: CiliumEndpointNotReady
      expr: cilium_endpoint_state{endpoint_state="waiting-for-identity"} > 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Endpoint stuck on {{ $labels.instance }}"

    - alert: CiliumAgentDown
      expr: up{job="cilium-agent-metrics"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Cilium agent unreachable on {{ $labels.instance }}"

    - alert: CiliumBPFMapPressure
      expr: cilium_bpf_map_pressure > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "BPF map {{ $labels.map_name }} near full on {{ $labels.instance }}"
```

### Diagnosis with Metrics
```bash
# Verify targets are up
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool | grep -E "health|lastError"

# Query drop reasons
curl -s "http://localhost:9090/api/v1/query?query=cilium_drop_count_total" \
  | python3 -m json.tool | grep -E "reason|value"

# Check endpoint states
curl -s "http://localhost:9090/api/v1/query?query=cilium_endpoint_state" \
  | python3 -m json.tool | grep -E "endpoint_state|value"
```

### Key Lesson
> Metrics + Hubble = complete observability.  
> `cilium_drop_count_total` với reason="Policy denied" → spike = policy change mới gây issue.  
> `cilium_endpoint_state` waiting-for-identity kéo dài > 30s → investigate agent logs.  
> Setup alerts trước khi go production, không phải sau khi incident.

---

## Scenario 9: CLI Troubleshooting Toolkit

### Background
Tổng hợp tất cả commands cần thiết để troubleshoot Cilium trong production. Organized theo use case để dễ reference khi có incident.

### Troubleshooting Decision Tree
```
Pod không connect được?
│
├─► hubble observe --verdict DROPPED --follow
│   │
│   ├─► "Policy denied" ?
│   │   └─► NetworkPolicy issue
│   │       kubectl get networkpolicy -A
│   │       cilium-dbg policy trace --src-k8s-pod ns/pod --dst-k8s-pod ns/pod --dport 80
│   │
│   ├─► DNS DROPPED to kube-system?
│   │   └─► Egress policy thiếu UDP 53 rule
│   │       Thêm egress rule cho kube-system:53/UDP
│   │
│   └─► Không có DROPPED flows?
│       ├─► Service issue? cilium-dbg bpf lb list | grep <ClusterIP>
│       └─► Node issue? cilium connectivity test --test health
│
Response 403 thay vì timeout?
│   └─► L7 CiliumNetworkPolicy → check header 'server: envoy'
│       kubectl get ciliumnetworkpolicy -A
│
Traffic skewed về 1 backend?
│   └─► cilium-dbg bpf lb list — backends registered đúng chưa?
│       Đổi algorithm: cilium config set bpf-lb-algorithm maglev
│
Cilium agent unhealthy?
    └─► kubectl -n kube-system logs ds/cilium --since=5m | grep -i error
        cilium-dbg status
        cilium connectivity test --test health
```

### Quick Health Check
```bash
# Tổng quan — chạy đầu tiên khi có vấn đề
cilium status

# Verbose với tất cả component details
cilium status --verbose

# Chờ đến khi cluster healthy (useful sau restart)
cilium status --wait

# Connectivity test toàn diện
cilium connectivity test
```

### Hubble Flow Commands
```bash
# Start port-forward (bắt buộc trước khi dùng hubble CLI)
cilium hubble port-forward &
hubble status

# Xem tất cả flows realtime
hubble observe --follow

# Chỉ xem DROPPED flows (quan trọng nhất)
hubble observe --verdict DROPPED --follow

# Flows của một pod cụ thể
hubble observe --pod default/client --follow

# Flows giữa 2 pods
hubble observe --from-pod default/client --to-pod default/webserver --follow

# DNS flows
hubble observe --protocol DNS --follow

# Flows trong 5 phút qua
hubble observe --since 5m

# JSON output để parse
hubble observe --output json | jq '.flow | "\(.source.pod_name) -> \(.destination.pod_name): \(.verdict)"'
```

### Agent & Node Debugging
```bash
# Exec vào cilium pod trên node cụ thể
NODE="worker1"
CILIUM_POD=$(kubectl get pods -n kube-system -o wide \
  | grep cilium | grep $NODE \
  | grep -v envoy | grep -v operator \
  | awk '{print $1}')
kubectl -n kube-system exec -it $CILIUM_POD -- cilium-dbg status

# Xem agent logs
kubectl -n kube-system logs $CILIUM_POD --since=5m
kubectl -n kube-system logs $CILIUM_POD --since=5m | grep -i "error\|warn\|fail"

# Xem startup flags (để debug config issues)
kubectl -n kube-system logs $CILIUM_POD | grep "^\s*--" | head -40
```

### Policy Debugging
```bash
# List tất cả policies
kubectl get networkpolicy -A
kubectl get ciliumnetworkpolicy -A

# Trace policy decision cho một flow cụ thể
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg policy trace \
  --src-k8s-pod default/client \
  --dst-k8s-pod default/webserver \
  --dport 80

# Xem tất cả identities trong cluster
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg identity list

# Xem identity của một pod cụ thể
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg identity list | grep "namespace=default"
```

### Endpoint Debugging
```bash
# List tất cả endpoints trên node hiện tại
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg endpoint list

# Get chi tiết endpoint (thay ENDPOINT_ID bằng số từ list)
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg endpoint get <ENDPOINT_ID>

# Xem CiliumEndpoints (Kubernetes objects)
kubectl get ciliumendpoints -A
kubectl get ciliumendpoints -n default
```

### eBPF Map Inspection
```bash
# LB table — Services và backends
CLUSTER_IP=$(kubectl get svc <service> -o jsonpath='{.spec.clusterIP}')
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg bpf lb list | grep $CLUSTER_IP

# NAT table — active translations
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf nat list | head -30

# Connection tracking
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf ct list global | head -20

# Tunnel endpoints (VXLAN)
kubectl -n kube-system exec -it ds/cilium -- cilium-dbg bpf tunnel list

# Trực tiếp trên node (không cần kubectl exec)
sudo bpftool prog list | grep sched_cls
sudo bpftool map list | grep cilium
```

### Configuration Management
```bash
# Xem tất cả config hiện tại
kubectl -n kube-system get configmap cilium-config -o yaml

# Set config value
cilium config set <key> <value>

# Apply config change
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium

# Verify config đã apply (xem startup flags trong logs)
kubectl -n kube-system logs ds/cilium | grep "<config-key>"
```

### Common Config Commands
```bash
# Enable BPF masquerading
cilium config set enable-bpf-masquerade true

# Switch LB algorithm
cilium config set bpf-lb-algorithm maglev   # consistent hashing
cilium config set bpf-lb-algorithm random   # random (default)

# Enable metrics
cilium config set prometheus-serve-addr ':9962'

# Verify kube-proxy replacement
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg status | grep KubeProxyReplacement
```

### Sysdump — Collect Debug Info
```bash
# Generate sysdump để gửi cho support hoặc lưu archive
kubectl -n kube-system exec -it ds/cilium -- \
  cilium-dbg sysdump > cilium-sysdump-$(date +%Y%m%d).zip

# Sysdump bao gồm:
# - cilium-dbg status output
# - Endpoint và policy state
# - BPF map dumps
# - Agent logs
# - Kubernetes events
```

### Quick Reference Table

| Task | Command |
|------|---------|
| Overall health | `cilium status` |
| Watch drops | `hubble observe --verdict DROPPED --follow` |
| Pod flows | `hubble observe --pod ns/pod --follow` |
| Policy trace | `cilium-dbg policy trace --src-k8s-pod ns/pod --dst-k8s-pod ns/pod` |
| Endpoint list | `cilium-dbg endpoint list` |
| LB backends | `cilium-dbg bpf lb list \| grep <ClusterIP>` |
| NAT table | `cilium-dbg bpf nat list` |
| Node list | `cilium-dbg node list` |
| All identities | `cilium-dbg identity list` |
| Agent logs | `kubectl -n kube-system logs ds/cilium --since=5m` |
| Connectivity test | `cilium connectivity test` |
| Generate sysdump | `cilium-dbg sysdump > dump.zip` |

### Common Issues Quick Fix

| Symptom | Likely cause | First action |
|---------|-------------|--------------|
| curl timeout, DNS OK | L4 policy block | `hubble --verdict DROPPED` |
| curl 000, IP direct OK | DNS egress blocked | Check DNS flows in Hubble |
| curl 403, server:envoy | L7 policy block | `kubectl get ciliumnetworkpolicy` |
| Pod stuck waiting-for-identity | Agent issue | Restart cilium pod on that node |
| Traffic only 1 backend | LB skew | `cilium-dbg bpf lb list` |
| Nodes NotReady | CNI not installed | `cilium status`, check DaemonSet |
| kube-proxy still running | Init without `--skip-phases` | Reinstall cluster |
| BPF masquerade not active | Wrong config key | Set `enable-bpf-masquerade true` |

---

## Summary: Troubleshooting Methodology

### The 3-Step Framework

```
1. OBSERVE   → hubble observe --verdict DROPPED
               Identify WHERE traffic is being dropped

2. DIAGNOSE  → cilium-dbg policy trace / endpoint get / bpf lb list
               Understand WHY it is being dropped

3. FIX       → kubectl apply / cilium config set
               Apply the correct fix and verify
```

### Golden Rules

1. **Hubble first** — xem DROPPED flows trước khi động vào bất cứ thứ gì
2. **DNS egress** — mọi Egress policy phải có UDP 53 rule đến kube-system
3. **Labels match** — `podSelector` và `namespaceSelector` dùng labels thực tế, không phải tên
4. **server: envoy** = L7 block; **timeout** = L4 block
5. **eBPF persists** — agent restart không gây downtime, eBPF maps survive
6. **Identity not IP** — Cilium policy dựa trên Security Identity, không phải IP address
