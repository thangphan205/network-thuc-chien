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

# Tập 23
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

## Stack Observability Calico (Production)

```
Felix (port 9091) ──► Prometheus ──► Grafana (Visual)
                            │
                            └──► AlertManager ──► Telegram (Native Integration)

Cài đặt chuyên nghiệp qua kube-prometheus-stack (Helm):
  - Prometheus Operator (Quản lý cấu hình động qua Custom Resource)
  - Prometheus Server & AlertManager (Gửi cảnh báo trực tiếp)
  - Grafana (Tích hợp sẵn Datasource & Sidecar Dashboard)
  - Node Exporter & kube-state-metrics (Thu thập metrics hạ tầng)
```

---

## ServiceMonitor — Cách Prometheus phát hiện targets

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
      k8s-app: calico-node    # Trỏ vào Service đại diện calico-node
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
```

**Nguyên lý hoạt động:**
`ServiceMonitor` -> `Prometheus Operator` phát hiện -> tự động sinh cấu hình scrape -> `Prometheus Server` kéo metrics từ endpoint port `9091` của Felix.

---

## Alert Rules & Native Telegram Config

**Alertmanager gửi trực tiếp tin nhắn Telegram không qua Webhook trung gian:**

```yaml
receivers:
- name: telegram
  telegram_configs:
  - bot_token: "<TELEGRAM_BOT_TOKEN>"
    chat_id: <TELEGRAM_CHAT_ID>
    send_resolved: true
    parse_mode: HTML
    message: |
      {{ if eq .Status "firing" }}🔴 <b>[FIRING] {{ .CommonLabels.alertname }}</b>{{ else }}✅ <b>[RESOLVED] {{ .CommonLabels.alertname }}</b>{{ end }}
      <b>Mức độ:</b> {{ .CommonLabels.severity }}
      <b>Mô tả:</b> {{ .CommonAnnotations.summary }}
```

---

## Kịch bản Demo Traffic thực tế

Để học viên thấy trực quan nhất, chúng ta triển khai mô hình sau:

```
[Normal User] ──► [Web Frontend] ──► [Web API] ──► [Database] (Cho phép)
                                                      ▲
[Rogue Actor] ────────────────────────────────────────┘ (Bị chặn & Drop)
```

- **Traffic Generator**: Tạo HTTP requests liên tục để mô phỏng traffic sạch (Allowed).
- **Rogue Scanner**: Liên tục quét cổng Database (Deny).
- **Calico NetworkPolicy**: Chặn đứng Rogue Scanner.
- **Kết quả**: Biểu đồ Grafana hiển thị đồng thời cả Normal Traffic và Deny Traffic (Spike).

---

## 4 Dashboards & Metrics cần có trong Production

| Dashboard Panel | PromQL Query | Ngưỡng Alert |
| :--- | :--- | :--- |
| **BGP Status** | `bgp_peers{status="Established"}` | `< 1` (Critical) |
| **Normal Traffic** | `rate(felix_active_local_endpoints[1m])` | Theo dõi hoạt động |
| **Deny Traffic** | `rate(felix_denied_packets_total[1m])` | `> 0.5 pkts/s` (Warning) |
| **Policy Calc Time** | `felix_calc_graph_update_time_seconds` | `p99 > 1s` (Warning) |

---

<!-- _class: lab -->

## 🔬 Lab Time: Triển khai Calico Observability

Chúng ta sẽ thực hành từng bước:

1. **Bật Felix metrics:** Cấu hình Felix expose metrics qua port 9091.
2. **Cài đặt kube-prometheus-stack:** Deploy qua Helm với native Telegram Alerting.
3. **Triển khai Demo App & Traffic Generator:** Chạy mock microservices và giả lập normal + rogue traffic.
4. **Cấu hình ServiceMonitor:** Cấu hình tự động thu thập Felix metrics.
5. **Thiết lập Alert Rules & Chặn Traffic:** Áp dụng NetworkPolicy, kích hoạt cảnh báo gửi về Telegram.
6. **Giám sát trên Grafana:** Import Dashboard và theo dõi trực quan lượng traffic.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Phần tiếp theo (Tập 24):** Tại sao Cilium? Pain points của Calico và sockops bypass.
