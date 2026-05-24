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
## Hubble Metrics: `hubble_drop_total`, `http_requests` — Đúng tool, đúng tình huống

**Phần 3 — Cilium** · `#hubble` `#metrics` `#prometheus` `#alerting` `#observability`

---

## Mục tiêu tập này

- Hubble Metrics: network metrics không cần code instrumentation
- Top 4 metrics cần monitor trong production
- Cấu hình Prometheus scrape Hubble + setup alerts
- Khi nào dùng Hubble CLI / UI / Metrics

**Prerequisites:** Cilium + kube-prometheus-stack (hoặc Prometheus standalone)

---

## Hubble Metrics: Zero-code network telemetry

```
Application metrics (cần code):
  prometheus_client.counter("requests_total").inc()
  → Dev phải code, instrument, deploy, restart

Hubble Metrics (zero-code):
  Cilium observe mọi flow → auto-generate metrics

Top metrics:
  hubble_drop_total                    ← Drop counter
  hubble_flows_processed_total         ← All flows
  hubble_http_requests_total           ← HTTP requests
  hubble_http_request_duration_seconds ← HTTP latency
  hubble_tcp_flags_total               ← TCP SYN/FIN/RST

Cấu hình 1 lần → metrics cho toàn cluster!
So với Calico: felix_denied_packets_total (L4 only)
Hubble: L4 + L7 HTTP + DNS level metrics
```

---

## Key Metrics: hubble_drop_total

```promql
# Rate drops (5 phút window)
rate(hubble_drop_total[5m])

# Chỉ Policy denied drops
rate(hubble_drop_total{reason="Policy denied"}[5m])

# Alert: spike in drops
rate(hubble_drop_total[5m]) > 10

# Drops per namespace
sum by (destination_namespace) (
  rate(hubble_drop_total{reason="Policy denied"}[5m])
)

# Top sources of drops
topk(5,
  sum by (source) (
    rate(hubble_drop_total[5m])
  )
)
```

---

## Key Metrics: HTTP và TCP

```promql
# HTTP request rate
rate(hubble_http_requests_total[5m])

# HTTP error ratio (5xx)
rate(hubble_http_requests_total{status="5.."}[5m])
/
rate(hubble_http_requests_total[5m])

# HTTP p99 latency
histogram_quantile(0.99,
  rate(hubble_http_request_duration_seconds_bucket[5m])
)

# TCP reset rate (connection issues)
rate(hubble_tcp_flags_total{flags="RST"}[5m])
```

---

## Enable Hubble Metrics

```bash
# Helm upgrade để enable metrics
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,http}"

# Verify metrics endpoint
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium -o name | head -1)

kubectl -n kube-system exec -it $CILIUM_POD -- \
  curl -s localhost:9965/metrics | grep "^hubble_" | head -10
# hubble_drop_total{...} 0
# hubble_flows_processed_total{...} 142
# hubble_http_requests_total{...} 87
```

---

## Alert Rules quan trọng

```yaml
- alert: HighDropRate
  expr: rate(hubble_drop_total{reason="Policy denied"}[5m]) > 50
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "High network policy drop rate"

- alert: HTTPErrorRateHigh
  expr: |
    rate(hubble_http_requests_total{status="5.."}[5m])
    / rate(hubble_http_requests_total[5m]) > 0.1
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "HTTP error rate > 10%"
```

---

## Tool selection: Đúng tool đúng tình huống

| Tình huống | Tool |
| :--- | :--- |
| Incident đang xảy ra → debug ngay | `hubble observe --verdict DROPPED --follow` |
| "Ai đang gọi ai trong cluster?" | Hubble UI Service Map |
| Alert khi drop rate spike | Hubble Metrics + AlertManager |
| Track HTTP latency over time | Hubble Metrics + Grafana |
| Postmortem: "5 phút trước xảy ra gì?" | Hubble UI flow history |
| Automation/CI check | `hubble observe --output json \| jq` |

```
Quy tắc đơn giản:
  Real-time debug   → hubble CLI
  Visual topology   → Hubble UI  
  Trends + alerts   → Hubble Metrics + Prometheus
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Enable Hubble Metrics + Setup Alerts

Chúng ta sẽ thực hành:

1. **Enable Hubble metrics** qua Helm upgrade và verify endpoint.
2. **Scrape metrics:** Tạo ServiceMonitor để Prometheus scrape.
3. **Generate traffic** để thấy metrics tăng trong Prometheus.
4. **Create PrometheusRule** với 2 alerts: HighDropRate và HTTPErrorRate.
5. **Trigger alert** bằng traffic bị deny và xem alert firing.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 39):** Troubleshooting Cilium — `cilium status` → `hubble observe` → `cilium monitor`.
