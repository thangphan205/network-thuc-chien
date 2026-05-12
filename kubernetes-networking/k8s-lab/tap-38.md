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

# Tập 38
## Hubble Metrics: hubble_drop_total, http_requests — Đúng tool, đúng tình huống

**Phần 3 — Cilium** · `#hubble` `#metrics` `#prometheus` `#alerting` `#observability`

---

## Mục tiêu tập này

- Hubble Metrics: network metrics không cần code instrumentation
- Top metrics cần theo dõi trong production
- Cấu hình Prometheus scrape Hubble metrics
- Khi nào dùng Hubble CLI/UI vs Hubble Metrics

---

## Hubble Metrics: Zero-code network telemetry

```
Application metrics (cần code):
  prometheus_client.counter("requests_total").inc()
  → Dev phải code, instrument, deploy

Hubble Metrics (zero-code):
  Cilium observe mọi flow → auto-generate metrics
  
  hubble_drop_total                 ← Dropped packets counter
  hubble_flows_processed_total      ← All flows (FORWARDED/DROPPED)
  hubble_http_requests_total        ← HTTP requests by method/status
  hubble_http_request_duration_seconds ← HTTP latency histogram
  hubble_tcp_flags_total            ← TCP SYN/FIN/RST counts

Không cần:
  - Thêm code vào application
  - Restart Pod
  - SDK integration

Cấu hình 1 lần → metrics cho toàn cluster!
```

---

## Key Metrics: hubble_drop_total

```promql
# Rate of dropped packets (policy denials)
rate(hubble_drop_total[5m])

# Breakdown by reason
rate(hubble_drop_total{reason="Policy denied"}[5m])

# Alert: sudden spike in drops
rate(hubble_drop_total[5m]) > 10

# Top sources of drops
topk(5,
  sum by (source) (
    rate(hubble_drop_total[5m])
  )
)

# Drops per namespace
sum by (destination_namespace) (
  rate(hubble_drop_total{reason="Policy denied"}[5m])
)
```

---

## Key Metrics: HTTP và TCP

```promql
# HTTP request rate (by service)
rate(hubble_http_requests_total[5m])

# HTTP error rate (5xx)
rate(hubble_http_requests_total{status="5.."}[5m])
/
rate(hubble_http_requests_total[5m])

# HTTP p99 latency
histogram_quantile(0.99,
  rate(hubble_http_request_duration_seconds_bucket[5m])
)

# TCP reset rate (connection issues)
rate(hubble_tcp_flags_total{flags="RST"}[5m])

# Active connections
hubble_flows_processed_total{type="L4",verdict="FORWARDED"}
```

---

## Cấu hình: Enable Hubble Metrics

```bash
multipass shell k8s-master

# Enable Hubble metrics khi cài Cilium
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,http}"

# Verify metrics endpoint
CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
  -o name | head -1)

kubectl -n kube-system exec -it $CILIUM_POD -- \
  curl -s localhost:9965/metrics | grep "hubble_" | head -20
```

---

## Lab: Deploy Prometheus và scrape Hubble

```bash
# Cài kube-prometheus-stack (nếu chưa có)
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123

# Tạo ServiceMonitor cho Hubble metrics
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: hubble-metrics
  namespace: monitoring
  labels:
    release: monitoring
spec:
  namespaceSelector:
    matchNames: [kube-system]
  selector:
    matchLabels:
      k8s-app: hubble
  endpoints:
  - port: hubble-metrics
    interval: 15s
    path: /metrics
EOF
```

---

## Lab: Create Grafana Dashboard

```bash
# Port-forward Grafana
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
# Browser: http://localhost:3000 (admin/admin123)

# Import Hubble dashboard (ID: 16611 từ grafana.com)
# Grafana → + → Import → 16611 → Load → Import

# Hoặc query thủ công:
# Panel 1: Drop rate
# rate(hubble_drop_total[5m])

# Panel 2: HTTP error ratio
# rate(hubble_http_requests_total{status="5.."}[5m])
# / rate(hubble_http_requests_total[5m])

# Panel 3: Policy denial heatmap
# sum by (destination_namespace, reason) (
#   rate(hubble_drop_total[5m])
# )
```

---

## Lab: Setup alerts

```bash
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: hubble-alerts
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
  - name: hubble.rules
    rules:
    - alert: HighDropRate
      expr: rate(hubble_drop_total{reason="Policy denied"}[5m]) > 50
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "High network policy drop rate"
        description: "{{ $value }} drops/sec in {{ $labels.destination_namespace }}"

    - alert: HTTPErrorRateHigh
      expr: |
        rate(hubble_http_requests_total{status="5.."}[5m])
        / rate(hubble_http_requests_total[5m]) > 0.1
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "HTTP error rate > 10%"
EOF
```

---

## Tool selection: Khi nào dùng gì?

| Tình huống | Tool |
| :--- | :--- |
| Incident đang xảy ra → debug ngay | `hubble observe --verdict DROPPED --follow` |
| "Ai đang gọi ai trong cluster?" | Hubble UI Service Map |
| Alert khi drop rate tăng đột ngột | Hubble Metrics + AlertManager |
| Track HTTP error rate over time | Hubble Metrics + Grafana |
| Postmortem: "5 phút trước xảy ra gì?" | Hubble UI flow history |
| Automation: count drops in CI/CD | `hubble observe --output json \| jq` |

```
Quy tắc đơn giản:
  Real-time debug → hubble CLI
  Visual topology → Hubble UI
  Trends + alerts → Hubble Metrics + Prometheus
```

---

## Key Takeaways

```
Hubble Metrics = Network metrics không cần instrument code

Top 4 metrics cần monitor ngay:
  1. hubble_drop_total         → Security policy violations
  2. hubble_http_requests_total → HTTP error rate
  3. hubble_http_request_duration_seconds → Latency
  4. hubble_tcp_flags_total{flags="RST"} → Connection resets

So sánh với Calico:
  Calico: cần Felix metrics (felix_denied_packets_total)
           + manual Prometheus setup
  Cilium: Hubble metrics tích hợp, richer data
           + HTTP/DNS level metrics (Calico không có)

Best practice: dùng cả 3 Hubble tools cùng lúc:
  Metrics → alert bạn "có vấn đề"
  UI      → locate "vấn đề ở đâu"
  CLI     → diagnose "vấn đề là gì"
```

> **Tập tiếp theo (Tập 39): Troubleshooting Cilium — cilium status → hubble observe → cilium CLI.**
