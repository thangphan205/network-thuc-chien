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
## Calico Observability: Prometheus + Grafana + AlertManager

**Phần 2 — Calico** · `#observability` `#prometheus` `#grafana` `#alertmanager` `#metrics`

---

## Mục tiêu tập này

- Bật Felix metrics endpoint trong Calico
- Deploy kube-prometheus-stack qua Helm
- Cấu hình ServiceMonitor để Prometheus scrape Felix
- Tạo PrometheusRule alerts cho BGP down và packet drop rate cao

**Prerequisites:** Cluster Calico đang chạy, Helm đã cài hoặc sẽ cài trong lab

---

## Felix Metrics — Những gì Calico expose

```bash
# Bật Felix metrics (port 9091 mặc định)
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"prometheusMetricsEnabled": true}}'

# Scrape thủ công từ node
curl http://<node-ip>:9091/metrics | grep -E "^felix_|^bgp_" | head -10
```

**Metrics quan trọng nhất:**

| Metric | Ý nghĩa |
| :--- | :--- |
| `bgp_peers{status="Established"}` | BGP sessions đang UP |
| `felix_denied_packets_total` | Packets bị NetworkPolicy DROP |
| `felix_active_local_endpoints` | Pods active trên node này |
| `felix_iptables_restore_calls_total` | Tần suất iptables update |
| `felix_calc_graph_update_time_seconds` | Policy calculation time |

---

## Stack Observability Calico

```
Felix (port 9091) ──► Prometheus ──► Grafana Dashboards
                            │
                            └──► AlertManager ──► Email/Slack/PagerDuty

Cài đặt qua kube-prometheus-stack (Helm chart):
  - Prometheus Operator
  - Prometheus
  - Grafana (với Datasource tự động)
  - AlertManager
  - Node Exporter
  - kube-state-metrics
```

---

## ServiceMonitor — Cách Prometheus biết scrape gì

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: calico-felix
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames: [calico-system]
  selector:
    matchLabels:
      k8s-app: calico-node    # Service có label này
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
```

**Luồng:**
```
ServiceMonitor → Prometheus Operator đọc → Prometheus config update
→ Prometheus scrape Service → Pull metrics từ Felix
→ Metrics available trong Prometheus/Grafana
```

---

## Alert Rules quan trọng

```yaml
# BGP session down — critical
- alert: CalicoBGPSessionDown
  expr: bgp_peers{status="Established"} < 1
  for: 2m
  labels: {severity: critical}

# Packet drop rate cao — warning (possible misconfigured policy)
- alert: CalicoHighDeniedPackets
  expr: rate(felix_denied_packets_total[1m]) > 0.5
  for: 10s
  labels: {severity: warning}

# Không có active endpoints — warning
- alert: CalicoEndpointDrop
  expr: felix_active_local_endpoints < 1
  for: 5m
  labels: {severity: warning}
```

---

## 4 Dashboards cần có trong production

| Dashboard | Query PromQL | Alert khi |
| :--- | :--- | :--- |
| **BGP Status** | `bgp_peers{status="Established"}` | < 1 per node |
| **Deny Rate** | `rate(felix_denied_packets_total[1m])` | > 100/s |
| **Endpoint Count** | `felix_active_local_endpoints` | < 1 per node |
| **Policy Calc Time** | `felix_calc_graph_update_time_seconds` | p99 > 1s |

---

<!-- _class: lab -->

## 🔬 Lab Time: Deploy Observability Stack

Chúng ta sẽ thực hành:

1. **Bật Felix metrics:** Patch FelixConfiguration và verify port 9091.
2. **Deploy kube-prometheus-stack:** Helm install Prometheus + Grafana + AlertManager.
3. **Cấu hình ServiceMonitor:** Prometheus tự động scrape Felix.
4. **Tạo Alert rules:** PrometheusRule cho BGP và packet drop.
5. **Trigger alert:** Generate traffic bị deny và xem alert FIRING.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Phần tiếp theo (Tập 27):** Tại sao Cilium? Pain points của Calico và sockops bypass.
