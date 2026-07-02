# Lab Tập 34: Hubble Metrics — hubble_drop_total, http_requests và alerts

Tập này enable Hubble metrics, scrape bằng Prometheus, tạo PrometheusRule alerts, và trigger alert bằng traffic thực tế.

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy (từ Tập 23).
- kube-prometheus-stack đang chạy (từ Tập 23, namespace `monitoring`) — hoặc sẽ cài trong lab này.

---

## 🔬 Thực nghiệm 1: Enable Hubble Metrics

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Enable Hubble metrics qua Helm upgrade:
   ```bash
   helm upgrade cilium cilium/cilium \
     --namespace kube-system \
     --reuse-values \
     --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2}"

   # Chờ cilium-agent restart
   kubectl -n kube-system rollout status daemonset/cilium
   ```
   > **💡 Lưu ý version:** Dùng `httpV2` chứ không phải `http` (đã deprecated). Khác biệt quan trọng: dưới flag `http` cũ, metric `http_requests_total` chỉ có label `method/protocol/reporter` — **không có `status`**. Alert rule `HTTPErrorRateHigh` ở Thực nghiệm 4 cần query theo `status=~"5.."`, nếu bật nhầm `http` thay vì `httpV2` thì label đó không tồn tại → query luôn ra rỗng → alert không bao giờ fire (silent fail, không báo lỗi rõ ràng).

2. Verify metrics endpoint active:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     curl -s localhost:9965/metrics | grep "^hubble_" | head -15
   # hubble_drop_total{reason="Policy denied",protocol="TCP"} 0
   # hubble_flows_processed_total{subtype="to-endpoint",...} 142
   # hubble_http_requests_total{method="GET",protocol="HTTP/1.1",status="200",...} 0
   ```
   > **💡 Lưu ý label:** `hubble_drop_total` chỉ có label `reason`/`protocol` mặc định — không có label `direction` trừ khi cấu hình thêm `labelsContext=traffic_direction` (lab này không bật), và nếu bật thì tên label đúng là `traffic_direction`, không phải `direction`.

3. Xem toàn bộ metric names:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     curl -s localhost:9965/metrics | grep "^# HELP hubble_" | awk '{print $3}'
   # hubble_drop_total
   # hubble_flows_processed_total
   # hubble_http_requests_total
   # hubble_http_request_duration_seconds
   # hubble_tcp_flags_total
   # hubble_dns_queries_total
   # ...
   ```

---

## 🔬 Thực nghiệm 2: Setup Prometheus scrape

**Trên `controlplane`:**

1. Cài kube-prometheus-stack nếu chưa có:
   ```bash
   helm repo add prometheus-community \
     https://prometheus-community.github.io/helm-charts 2>/dev/null || true
   helm repo update

   helm install monitoring prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace \
     --set grafana.adminPassword=admin123 \
     --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
     --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
     --set prometheus.prometheusSpec.resources.limits.memory=1Gi \
     --set grafana.resources.requests.memory=128Mi \
     --set grafana.resources.limits.memory=256Mi \
     2>/dev/null || echo "Already installed"
   ```

2. Tạo Service expose Hubble metrics:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Service
   metadata:
     name: hubble-metrics
     namespace: kube-system
     labels:
       k8s-app: hubble
   spec:
     selector:
       k8s-app: cilium
     ports:
     - name: hubble-metrics
       port: 9965
       targetPort: 9965
   EOF
   ```

3. Tạo ServiceMonitor:
   ```bash
   kubectl apply -f - <<'EOF'
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

4. Verify Prometheus scraping:
   ```bash
   kubectl -n monitoring port-forward \
     svc/monitoring-kube-prometheus-prometheus 9090:9090 &
   sleep 5

   # Query test
   curl -s 'http://localhost:9090/api/v1/query?query=hubble_drop_total' \
     | python3 -m json.tool | grep '"status"'
   # "status": "success"  ✅ Hubble metrics available!
   ```

---

## 💥 Thực nghiệm 3: Generate traffic và xem metrics tăng

**Trên `controlplane`:**

1. Deploy test pods với policy:
   ```bash
   kubectl create namespace production 2>/dev/null || true

   kubectl apply -n production -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: target
     labels:
       app: target
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "8080"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: attacker
     labels:
       app: attacker
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF

   # Default deny
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny
   spec:
     podSelector: {}
     policyTypes: [Ingress, Egress]
   EOF

   kubectl -n production wait --for=condition=Ready \
     pod/target pod/attacker --timeout=60s
   TARGET_IP=$(kubectl -n production get pod target \
     -o jsonpath='{.status.podIP}')
   ```

2. Generate denied traffic:
   ```bash
   kubectl -n production exec attacker -- bash -c "
     for i in \$(seq 1 50); do
       nc -zv -w 1 $TARGET_IP 8080 &>/dev/null
       sleep 0.1
     done
     echo 'Done'
   "
   ```

3. Xem hubble_drop_total tăng:
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=hubble_drop_total' \
     | python3 -m json.tool | grep '"value"'
   # "value": ["timestamp", "50"]  ← 50 drops!

   # Rate (per second):
   curl -s 'http://localhost:9090/api/v1/query?query=rate(hubble_drop_total[5m])' \
     | python3 -m json.tool | grep '"value"'
   # "value": ["timestamp", "1.6"]  ← ~1.6 drops/sec
   ```

---

## 🔬 Thực nghiệm 4: Create PrometheusRule alerts

**Trên `controlplane`:**

1. Create alert rules:
   ```bash
   kubectl apply -f - <<'EOF'
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
       - alert: HighNetworkDropRate
         expr: rate(hubble_drop_total{reason="Policy denied"}[5m]) > 5
         for: 1m
         labels:
           severity: warning
         annotations:
           summary: "High network policy drop rate in {{ $labels.destination_namespace }}"
           description: "{{ $value | humanize }} drops/sec being denied"

       - alert: HTTPErrorRateHigh
         expr: |
           (rate(hubble_http_requests_total{status=~"5.."}[5m])
           / rate(hubble_http_requests_total[5m])) > 0.1
         for: 5m
         labels:
           severity: critical
         annotations:
           summary: "HTTP error rate > 10%"
           description: "{{ $value | humanizePercentage }} HTTP errors from {{ $labels.source }}"
   EOF
   ```

2. Verify rules loaded:
   ```bash
   curl -s 'http://localhost:9090/api/v1/rules' \
     | python3 -m json.tool | grep '"name"' | grep -i "hubble\|High\|HTTP"
   # "name": "HighNetworkDropRate"
   # "name": "HTTPErrorRateHigh"
   ```

3. Generate traffic để trigger HighNetworkDropRate:
   > **💡 Lưu ý timing:** Traffic bị policy DROP không có phản hồi (không RST) nên mỗi lần `nc -zv -w 1` phải đợi hết timeout 1s trước khi thử lại — vòng lặp 200 lần thực chất kéo dài **~3-4 phút** (200 × ~1.05s), đủ dài để giữ rate cao suốt cửa sổ `for: 1m` của rule. Nếu bạn rút ngắn số lần lặp hoặc bỏ `-w 1`, hãy đảm bảo traffic vẫn chạy liên tục ít nhất ~70-90s để alert có đủ thời gian chuyển từ PENDING sang FIRING.
   ```bash
   kubectl -n production exec attacker -- bash -c "
     for i in \$(seq 1 200); do
       nc -zv -w 1 $TARGET_IP 8080 &>/dev/null
       sleep 0.05
     done
   " &

   echo "Chờ 60 giây để alert PENDING → FIRING..."
   sleep 65

   # Xem alert status:
   curl -s 'http://localhost:9090/api/v1/alerts' \
     | python3 -m json.tool | grep -A5 "HighNetworkDropRate"
   # "state": "firing"  ← Alert đang FIRING!
   ```

4. Xem Grafana dashboard (optional):
   ```bash
   kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
   # Browser: http://localhost:3000 (admin/admin123)
   # Import Hubble dashboard ID: 16613 (từ grafana.com — 16611 là "Cilium Agent Metrics", khác dashboard)
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete networkpolicy default-deny
kubectl -n production delete pod target attacker
kubectl -n monitoring delete prometheusrule hubble-alerts
kubectl delete svc hubble-metrics -n kube-system
kubectl -n monitoring delete servicemonitor hubble-metrics
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Zero-code network telemetry:** Enable bằng Helm `hubble.metrics.enabled` → tự động có metrics cho toàn cluster — không cần instrument application code, không cần restart pods.
2. **Top 4 metrics production:** `hubble_drop_total` (security violations), `hubble_http_requests_total` (error rate — cần bật `httpV2` để có label `status`), `hubble_http_request_duration_seconds` (latency), `hubble_tcp_flags_total{flag="RST"}` (connection resets — label số ít `flag`, không phải `flags`).
3. **Hubble vs Calico metrics:** Calico chỉ có `felix_denied_packets_total` (L4 only). Hubble có L4 + HTTP level metrics (method, status code, latency) — không cần setup Jaeger hay application instrumentation.
4. **3 tools = 3 vai trò:** CLI (`hubble observe`) → alert bạn "có vấn đề"; UI (Service Map) → locate "vấn đề ở đâu"; Metrics (Prometheus) → track trends và alert tự động khi vượt ngưỡng.
