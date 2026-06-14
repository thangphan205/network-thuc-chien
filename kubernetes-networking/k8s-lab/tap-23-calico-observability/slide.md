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

## GitOps Deployment Blueprint (Argo CD)

**Trong Production, toàn bộ Monitoring Stack được khai báo dưới dạng mã (YAML):**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-stack
  namespace: argocd
spec:
  source:
    chart: kube-prometheus-stack
    repoURL: https://prometheus-community.github.io/helm-charts
    targetRevision: 61.3.0 # Khóa cứng phiên bản Helm
    helm:
      valueFiles:
      - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
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

## Secrets & AlertmanagerConfig CRD (Production)

**Không hardcode Secrets/Token vào Git! Sử dụng Kubernetes Secret + CRD:**

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: telegram-security-alerts
  namespace: monitoring
  labels:
    release: monitoring # Tự động phát hiện bởi Prometheus Operator
spec:
  route:
    receiver: telegram-secops
  receivers:
  - name: telegram-secops
    telegramConfigs:
    - botToken:
        name: alertmanager-telegram-secret # Tên K8s Secret
        key: token                         # Key chứa Bot Token
      chatId: -1001234567890
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

## Incident Response chuẩn Production (SANS/NIST)

**Không xoá Pod ngay lập tức khi phát hiện bị tấn công!**

1. **Phát hiện (Detection)**: Alertmanager bắn cảnh báo `CalicoHighDeniedPackets` sang Telegram.
2. **Cô lập (Containment)**: Cách ly mạng bằng **Network Policy (Deny-All)** & Dán nhãn Pod.
   - Pod bị ngắt kết nối mạng hoàn toàn nhưng **vẫn hoạt động** để phục vụ phân tích.
3. **Điều tra (Forensics)**: Chạy lệnh `kubectl exec` kiểm tra tiến trình, logs, mã độc trong bộ nhớ.
4. **Triệt tiêu (Eradication)**: Xoá bỏ triệt để Pod hoặc hạ tầng chứa lỗ hổng bảo mật.

---

## Cấu hình Quarantine Policy (Cách ly mạng)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      security-status: quarantined
  policyTypes: [Ingress, Egress]
```

- Nhãn cách ly: `security-status: quarantined`
- Bỏ trống `ingress`/`egress` -> **Mặc định chặn 100% kết nối đi vào/ra (Deny-All)**.
- Kích hoạt bằng lệnh: `kubectl label pod <pod-name> security-status=quarantined`

---

## GitOps Dashboard & Custom Security Panels

**Dashboard-as-Code (GitOps) thực tế:**
- Lưu trữ file JSON Dashboard vào `ConfigMap`.
- Thêm nhãn: `grafana_dashboard="1"`.
- Grafana **Sidecar** tự động phát hiện, đồng bộ và hiển thị dashboard không cần nạp thủ công.

**Biểu đồ Custom Security Dashboard cần có:**
1. **Denied Packet Rate (Time Series)**:
   - Query: `sum by (instance) (rate(felix_denied_packets_total[1m]))` (Đơn vị: `pps`)
2. **Legitimate Workloads (Stat/Gauge)**:
   - Query: `felix_active_local_endpoints` (Độ ổn định của ứng dụng hợp lệ)

---

<!-- _class: lab -->

## 🔬 Lab Time: Triển khai Calico Observability

Chúng ta sẽ thực hành từng bước:

1. **Bật Felix metrics:** Cấu hình Felix expose metrics qua port 9091.
2. **Cài đặt kube-prometheus-stack:** Helm deploy với NodePorts `30090` (Prom) / `32300` (Grafana).
3. **Triển khai Demo App & Traffic Generator:** Giả lập healthy baseline & rogue traffic.
4. **Cấu hình ServiceMonitor:** Cấu hình tự động thu thập Felix metrics.
5. **Thiết lập Rules & Incident Response:** Áp dụng NetworkPolicy, cách ly mạng (Quarantine) & Telegram Alerts.
6. **Giám sát trên Grafana:** Xem GitOps Dashboard & Tạo Custom Security Panel (Denied vs Active).

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Phần tiếp theo (Tập 24):** Tại sao Cilium? Pain points của Calico và sockops bypass.
