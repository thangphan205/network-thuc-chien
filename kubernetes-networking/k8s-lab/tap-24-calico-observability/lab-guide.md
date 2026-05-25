# Lab Tập 24: Calico Observability — Prometheus + Grafana + AlertManager

Tập này dựng stack observability đầy đủ cho Calico: Felix metrics → Prometheus → Grafana → AlertManager alerts.

### Sơ đồ kiến trúc giám sát: Calico Observability Flow

```mermaid
graph TD
  subgraph Kubernetes Nodes (DaemonSet)
    A1["Node 1: calico-node<br/>(Felix & BIRD)"] -- "Exposes metrics<br/>Port 9091" --> S
    A2["Node 2: calico-node<br/>(Felix & BIRD)"] -- "Exposes metrics<br/>Port 9091" --> S
    A3["Node 3: calico-node<br/>(Felix & BIRD)"] -- "Exposes metrics<br/>Port 9091" --> S
  end

  subgraph Service Discovery (calico-system)
    S["Service: calico-felix-metrics<br/>(Selector: k8s-app=calico-node)"]
  end

  subgraph Prometheus Stack (monitoring)
    SM["ServiceMonitor: calico-felix<br/>(Spec.selector: k8s-app=calico-node)"] -.->|Discovers| S
    PO["Prometheus Operator"] -->|Reads ServiceMonitor| SM
    PO -->|Configures Scrape Targets| P["Prometheus Server"]
    P -->|Pull Metrics /metrics| S
    
    PR["PrometheusRule: calico-alerts"] -->|Defines Alert Rules| P
    P -->|Alert Firing| AM["AlertManager"]
  end

  subgraph Visualization
    G["Grafana Dashboards"] -->|Queries API| P
  end

  style A1 fill:#1e1e38,stroke:#a78bfa,stroke-width:2px,color:#e2e8f0
  style A2 fill:#1e1e38,stroke:#a78bfa,stroke-width:2px,color:#e2e8f0
  style A3 fill:#1e1e38,stroke:#a78bfa,stroke-width:2px,color:#e2e8f0
  style S fill:#152a2a,stroke:#34d399,stroke-width:2px,color:#a7f3d0
  style SM fill:#2d1b69,stroke:#f59e0b,stroke-width:2px,color:#fde68a
  style PO fill:#2d1b69,stroke:#a78bfa,stroke-width:2px,color:#e2e8f0
  style P fill:#0f172a,stroke:#3b82f6,stroke-width:2px,color:#bfdbfe
  style AM fill:#2d080a,stroke:#f87171,stroke-width:2px,color:#fca5a5
  style G fill:#1e293b,stroke:#ec4899,stroke-width:2px,color:#fbcfe8
```

---

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico đang chạy (từ Tập 9+).
- Ít nhất 4GB RAM trống trên cluster (kube-prometheus-stack khá nặng).
- Kết nối internet để pull Helm chart và images.

---

## 🔬 Thí nghiệm 1: Bật Felix metrics và verify

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Bật Felix metrics endpoint:
   ```bash
   kubectl patch felixconfiguration default \
     --type merge \
     --patch '{"spec": {"prometheusMetricsEnabled": true}}'
   ```

2. Verify FelixConfiguration:
   ```bash
   kubectl get felixconfiguration default -o yaml | grep prometheus
   # prometheusMetricsEnabled: true
   ```

3. Chờ Felix reload (~10 giây) rồi scrape thủ công từ worker1:
   ```bash
   WORKER1_IP=$(multipass info worker1 | grep IPv4 | awk '{print $2}')
   curl -s http://$WORKER1_IP:9091/metrics | grep -E "^felix_|^bgp_" | head -15
   # felix_active_local_endpoints 2
   # bgp_peers{status="Established",ip_version="IPv4"} 2
   # felix_denied_packets_total 0
   # felix_iptables_restore_calls_total 5
   # ...
   ```
   *Nhận xét:* Felix expose metrics dạng Prometheus text format trên mỗi Node.

---

## 🚀 Thí nghiệm 2: Cài Helm và deploy kube-prometheus-stack

**Trên `controlplane`:**

1. Cài Helm nếu chưa có:
   ```bash
   which helm || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   helm version
   ```

2. Thêm Prometheus community repo:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   ```

3. Cài kube-prometheus-stack với resource limits phù hợp lab:
   ```bash
   helm install monitoring prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace \
     --set grafana.adminPassword=admin123 \
     --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
     --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
     --set prometheus.prometheusSpec.resources.limits.memory=1Gi \
     --set grafana.resources.requests.memory=128Mi \
     --set grafana.resources.limits.memory=256Mi \
     --set alertmanager.alertmanagerSpec.resources.requests.memory=64Mi
   ```

4. Theo dõi deploy (mất 3-5 phút):
   ```bash
   watch kubectl -n monitoring get pods
   # Chờ đến khi tất cả Running (prometheus-0, grafana-xxx, alertmanager-0...)
   ```

---

## 🔬 Thí nghiệm 3: Cấu hình ServiceMonitor và Service cho Felix

**Trên `controlplane`:**

1. Tạo Service expose Felix metrics:
   ```bash
   kubectl apply -n calico-system -f - <<'EOF'
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

2. Tạo ServiceMonitor:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: calico-felix
     namespace: monitoring
     labels:
       release: monitoring
   spec:
     namespaceSelector:
       matchNames:
       - calico-system
     selector:
       matchLabels:
         k8s-app: calico-node
     endpoints:
     - port: metrics
       interval: 15s
       path: /metrics
   EOF
   ```

3. Verify ServiceMonitor được tạo:
   ```bash
   kubectl -n monitoring get servicemonitor calico-felix
   ```

4. Chờ Prometheus config reload (~30 giây) rồi verify target:
   ```bash
   # Port-forward Prometheus UI
   kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
   # Browser: http://localhost:9090/targets → tìm "calico-felix"
   # Status phải là UP
   ```

---

## 🔬 Thí nghiệm 4: Query metrics trong Prometheus

**Trên `controlplane`:**

1. Port-forward Prometheus (nếu chưa):
   ```bash
   kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
   ```

2. Query metrics Felix (mở browser `http://localhost:9090`):
   ```
   # BGP sessions UP (Số phiên BGP đang hoạt động):
   bgp_peers{status="Established"}

   # Packet deny rate (Tần suất gói tin bị chặn trong 1 phút):
   rate(felix_denied_packets_total[1m])

   # Active endpoints per node (Số Pod đang chạy trên mỗi Node):
   felix_active_local_endpoints

   # Policy calculation time histogram (Thời gian tính toán Policy p99):
   histogram_quantile(0.99, felix_calc_graph_update_time_seconds_bucket)
   ```

3. Verify data từ cả 3 nodes:
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=felix_active_local_endpoints' \
     | python3 -m json.tool | grep -E '"node"|"value"'
   # Thấy data từ controlplane, worker1, worker2
   ```

---

## 🔬 Thí nghiệm 5: Tạo Alert rules

**Trên `controlplane`:**

1. Tạo PrometheusRule với 3 alerts:
   ```bash
   kubectl apply -f - <<'EOF'
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
          expr: bgp_peers{status="Established"} < 1
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "BGP session down on {{ $labels.node }}"
            description: "Node {{ $labels.node }} has no established BGP peers for 2+ minutes"

        - alert: CalicoHighDeniedPackets
          expr: rate(felix_denied_packets_total[1m]) > 0.5
          for: 10s
          labels:
            severity: warning
          annotations:
            summary: "High packet drop rate on {{ $labels.node }}"
            description: "{{ $value | humanize }} packets/sec being denied by NetworkPolicy on {{ $labels.node }}"

        - alert: CalicoEndpointDrop
          expr: felix_active_local_endpoints < 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "No active endpoints on {{ $labels.node }}"
            description: "Node {{ $labels.node }} has no active Calico endpoints for 5+ minutes"
    EOF
   ```

2. Verify rule được load:
   ```bash
   # Prometheus UI: http://localhost:9090/rules → tìm "calico.rules"
   curl -s 'http://localhost:9090/api/v1/rules' \
     | python3 -m json.tool | grep "calico"
   ```

---

## 💥 Thí nghiệm 6: Trigger alert và xem firing

**Trên `controlplane`:**

1. Setup môi trường để tạo denied packets:
   ```bash
   kubectl create namespace production 2>/dev/null || true

   # Apply default deny
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny
   spec:
     podSelector: {}
     policyTypes:
     - Ingress
     - Egress
   EOF

   # Deploy target pod
   kubectl run target -n production --image=nicolaka/netshoot \
     -- nc -lk -p 8080
   kubectl run attacker -n production --image=nicolaka/netshoot \
     -- sleep infinity
   kubectl -n production wait --for=condition=Ready pod/target pod/attacker --timeout=60s
   TARGET_IP=$(kubectl -n production get pod target -o jsonpath='{.status.podIP}')
   ```

2. Generate traffic bị deny để trigger alert:
   ```bash
    kubectl -n production exec attacker -- bash -c "
      for i in \$(seq 1 100); do
        nc -zv -w 1 $TARGET_IP 8080 &>/dev/null &
        sleep 0.01
      done
      wait
      echo 'Done generating denied traffic (100 parallel scans completed!)'
    "
   ```

3. Xem metrics tăng:
   ```bash
   curl -s http://$WORKER1_IP:9091/metrics | grep felix_denied_packets_total
   # felix_denied_packets_total{...} XXX  ← Đang tăng
   ```

4. Xem alert trong Prometheus:
   ```bash
   # Browser: http://localhost:9090/alerts
   # CalicoHighDeniedPackets → PENDING (chờ 1 phút) → FIRING
   ```

---

## 🔬 Thí nghiệm 7: Truy cập Grafana và import dashboard

**Trên `controlplane`:**

1. Port-forward Grafana:
   ```bash
   kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
   # Browser: http://localhost:3000
   # Login: admin / admin123
   ```

2. Verify Prometheus datasource đã tự động được cấu hình:
   ```
   Grafana → Configuration → Data Sources → Prometheus
   URL: http://monitoring-kube-prometheus-prometheus:9090
   Status: Data source is working
   ```

3. Import Calico dashboard (nếu muốn dùng dashboard có sẵn):
   ```
   Grafana → + → Import → Nhập ID: 12175 → Load
   (Calico Felix Dashboard từ grafana.com)
   ```

4. Tạo custom panel nhanh:
   ```
   Grafana → + → Dashboard → Add panel
   Query: bgp_peers{status="Established"}
   Legend: {{instance}}
   Title: BGP Sessions per Node
   Save
   ```

---

## 🧹 Dọn dẹp (tùy chọn)

```bash
# Giữ lại nếu muốn tiếp tục dùng cho lab sau
# Hoặc xóa để giải phóng tài nguyên:
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring production
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"prometheusMetricsEnabled": false}}'

# Kill port-forward processes
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Felix tự expose metrics:** Chỉ cần patch `prometheusMetricsEnabled: true` → port 9091 active trên mỗi node.
2. **ServiceMonitor = discovery config:** Prometheus Operator đọc ServiceMonitor → tự config scrape jobs — không cần sửa Prometheus config thủ công.
3. **4 metrics cốt lõi cần monitor:** BGP peers established, denied packets rate, active endpoints, policy calc time.
4. **Alert thứ tự ưu tiên:** BGP down (critical) > High deny rate (warning: có thể policy sai) > No endpoints (warning: node issue).
5. **Limitation:** Calico observability cần tự setup stack. Cilium (Tập 25+) có Hubble built-in — flow visibility không cần setup thêm gì.
