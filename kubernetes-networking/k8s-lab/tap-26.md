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

# Tập 26
## Calico Observability: Prometheus + Grafana + AlertManager miễn phí

**Phần 2 — Calico** · `#observability` `#prometheus` `#grafana` `#alertmanager` `#metrics`

---

## Mục tiêu tập này

- Bật Felix metrics endpoint trong Calico
- Deploy Prometheus scrape Felix metrics
- Tạo Grafana dashboard: BGP, NetworkPolicy, Pod connectivity
- Cấu hình AlertManager alert khi BGP down hoặc packet drop tăng

**Prerequisites:** Cluster Calico đang chạy. Kube-prometheus-stack helm chart.

---

## Felix Metrics — Những gì Calico expose

```bash
# Bật Felix metrics
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"prometheusMetricsEnabled": true}}'

# Port mặc định: 9091
curl http://<node-ip>:9091/metrics | grep "^felix_" | head -20

# Metrics quan trọng nhất:
felix_bgp_peers_total{state="established"}   # BGP sessions đang UP
felix_denied_packets_total                   # Packets bị policy DROP
felix_active_local_endpoints                 # Pods active trên node này
felix_iptables_restore_calls_total           # Tần suất iptables update
felix_int_dataplane_addr_msg_batch_size      # Batch size updates
felix_calc_graph_update_time_seconds         # Policy calc time
```

---

## Deploy kube-prometheus-stack

```bash
multipass shell k8s-master

# Cài Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Thêm prometheus-community repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Cài kube-prometheus-stack (Prometheus + Grafana + AlertManager)
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Theo dõi deploy
kubectl -n monitoring get pods -w
# Sau 3-5 phút: tất cả Running
```

---

## Lab: Cấu hình ServiceMonitor cho Felix

```bash
# Tạo ServiceMonitor để Prometheus tự scrape Felix
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: calico-felix
  namespace: monitoring
  labels:
    release: monitoring  # Phải match label của Prometheus stack
spec:
  namespaceSelector:
    matchNames: [calico-system]
  selector:
    matchLabels:
      k8s-app: calico-node
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
EOF

# Tạo Service expose Felix metrics (port 9091)
kubectl apply -n calico-system -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: calico-felix-metrics
  labels:
    k8s-app: calico-node
spec:
  selector:
    k8s-app: calico-node
  ports:
  - name: metrics
    port: 9091
    targetPort: 9091
EOF
```

---

## Lab: Truy cập Grafana và tạo Dashboard

```bash
# Port-forward Grafana
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
# Mở browser: http://localhost:3000 (admin/admin123)

# Hoặc từ macOS host:
GRAFANA_SVC=$(kubectl -n monitoring get svc monitoring-grafana -o jsonpath='{.spec.clusterIP}')
# ssh tunnel qua Multipass

# Import Calico dashboard (ID: 12175 từ grafana.com)
# Grafana → + → Import → 12175 → Load

# Query PromQL cho BGP dashboard:
# felix_bgp_peers_total{state="established"}
# rate(felix_denied_packets_total[5m])
# felix_active_local_endpoints
```

---

## Lab: Cấu hình AlertManager rules

```bash
# Tạo PrometheusRule cho Calico alerts
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: calico-alerts
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
  - name: calico.rules
    rules:
    - alert: CalicoBGPSessionDown
      expr: felix_bgp_peers_total{state="established"} < 1
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "BGP session down on {{ $labels.node }}"
        description: "Node {{ $labels.node }} has no established BGP peers"

    - alert: CalicoHighDeniedPackets
      expr: rate(felix_denied_packets_total[5m]) > 100
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High packet drop rate on {{ $labels.node }}"
        description: "{{ $value }} packets/sec being denied by NetworkPolicy"

    - alert: CalicoEndpointDrop
      expr: felix_active_local_endpoints < 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "No active endpoints on {{ $labels.node }}"
EOF
```

---

## Lab: Trigger và verify alerts

```bash
# Trigger CalicoHighDeniedPackets: Generate traffic bị deny
kubectl -n production exec frontend -- bash -c '
  for i in $(seq 1 200); do
    nc -zv <database-ip> 5432 &>/dev/null
    sleep 0.1
  done
'

# Xem metrics tăng real-time
curl http://<node-ip>:9091/metrics | grep felix_denied_packets_total
# felix_denied_packets_total{...} 200  ← Đang tăng

# Trong Grafana: Alerting → Alert Rules → thấy alert FIRING
# AlertManager gửi thông báo (nếu đã cấu hình email/Slack receiver)

# Xem alert history
kubectl -n monitoring port-forward svc/monitoring-alertmanager 9093:9093 &
# Browser: http://localhost:9093
```

---

## Key Takeaways

**4 Dashboards cần có:**

| Dashboard | Query PromQL | Alert khi |
| :--- | :--- | :--- |
| BGP Status | `felix_bgp_peers_total{state="established"}` | < 1 per node |
| Deny Rate | `rate(felix_denied_packets_total[5m])` | > 100/s |
| Endpoint Count | `felix_active_local_endpoints` | < 1 per node |
| Policy Calc Time | `felix_calc_graph_update_time_seconds` | p99 > 1s |

**Khi nào cần Calico Observability:**
```
✅ Production cluster (cần biết khi có sự cố)
✅ Security audit (thống kê deny rate)
✅ BGP monitoring (critical cho routing)
⚠️  Tự build stack = overhead setup ban đầu
→ Cilium với Hubble built-in giải quyết overhead này
```

> **Phần tiếp theo (Tập 27): Tại sao Cilium? Pain points của Calico và sockops bypass.**
