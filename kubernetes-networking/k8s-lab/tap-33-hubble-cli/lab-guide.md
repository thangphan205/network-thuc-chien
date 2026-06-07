# Lab Tập 33: Hubble CLI — Debug network flows real-time

Tập này setup hubble CLI, dùng `hubble observe` để debug "pod không connect được" trong vòng 30 giây mà không cần SSH hay tcpdump.

## 🛠 Yêu cầu chuẩn bị
- Cilium + Hubble Relay running (từ Tập 24).
- `hubble` CLI cài trên máy local (macOS: `brew install hubble`).
- Hoặc dùng `hubble` trong cilium-agent container trực tiếp.

---

## 🔬 Thực nghiệm 1: Setup hubble CLI và verify connection

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Verify Hubble Relay đang running:
   ```bash
   kubectl -n kube-system get pods | grep hubble
   # hubble-relay-xxxxx    1/1  Running
   # hubble-ui-xxxxx       2/2  Running (nếu enabled)
   ```

2. Port-forward Hubble Relay:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2
   echo "Hubble Relay port-forward active on :4245"
   ```

3. Verify hubble CLI connection:
   ```bash
   # Nếu hubble đã cài:
   hubble status
   # Healthcheck (via localhost:4245): Ok
   # Current/Max Flows: 4096/4096 (100%)
   # Flows/s: 12.4
   # Connected Nodes: 3/3  ← Tất cả nodes

   # Nếu chưa cài hubble CLI — dùng kubectl exec:
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)
   alias hubble="kubectl -n kube-system exec -it $CILIUM_POD -- hubble"
   hubble observe --last 5
   ```

---

## 💥 Thực nghiệm 2: Deploy production stack và reproduce incident

**Trên `controlplane`:**

1. Setup namespace và pods:
   ```bash
   kubectl create namespace production 2>/dev/null || true

   kubectl apply -n production -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: backend
     labels:
       app: backend
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "8080"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: frontend
     labels:
       app: frontend
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF

   # Apply default deny — simulate production incident
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
     pod/backend pod/frontend --timeout=60s
   BACKEND_IP=$(kubectl -n production get pod backend \
     -o jsonpath='{.status.podIP}')
   ```

2. Reproduce "connection refused":
   ```bash
   kubectl -n production exec frontend -- \
     nc -zv -w 3 $BACKEND_IP 8080
   # (timeout) ← Không biết tại sao!
   ```

---

## 🔬 Thực nghiệm 3: Debug với Hubble trong 30 giây

**Trên `controlplane`:**

1. Start Hubble observer trước khi reproduce:
   ```bash
   # Bước 1: Open Hubble watch (real-time follow)
   hubble observe --namespace production \
     --verdict DROPPED --follow &
   HUBBLE_PID=$!
   ```

2. Trigger lại connection:
   ```bash
   # Bước 2: Trigger traffic
   kubectl -n production exec frontend -- \
     nc -zv -w 3 $BACKEND_IP 8080 &>/dev/null || true

   sleep 2

   # Bước 3: Hubble output xuất hiện ngay!
   # production/frontend → production/backend:8080  DROPPED  Policy denied
   # → Đây là vấn đề! Default deny policy block traffic

   kill $HUBBLE_PID 2>/dev/null
   ```

3. Fix policy:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-frontend-to-backend
   spec:
     podSelector:
       matchLabels:
         app: backend
     policyTypes: [Ingress]
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: frontend
       ports:
       - {protocol: TCP, port: 8080}
   EOF
   ```

4. Verify fix với Hubble:
   ```bash
   hubble observe --namespace production \
     --from-pod production/frontend \
     --to-pod production/backend &
   HUBBLE_PID=$!

   kubectl -n production exec frontend -- \
     nc -zv -w 3 $BACKEND_IP 8080

   sleep 2
   # Hubble: production/frontend → production/backend:8080  FORWARDED ✅
   kill $HUBBLE_PID 2>/dev/null
   ```

---

## 🔬 Thực nghiệm 4: Cheat sheet drills — thực hành filter patterns

**Trên `controlplane`:**

1. Xem tất cả DROPPED flows trong namespace:
   ```bash
   hubble observe --namespace production \
     --verdict DROPPED --last 20
   ```

2. JSON output và parse với jq:
   ```bash
   hubble observe --namespace production \
     --verdict DROPPED --output json --last 5 \
     | jq -r '.flow | "\(.source.pod_name) → \(.destination.pod_name):\(.l4.TCP.destination_port // "?")"'
   # frontend → backend:8080
   ```

3. Xem DNS flows (phát hiện DNS issues):
   ```bash
   hubble observe --namespace production \
     --protocol dns --last 10
   # Thấy DNS queries từ pods — check xem có fail không
   ```

4. Xem theo port (tìm database connection issues):
   ```bash
   hubble observe --to-port 5432 --verdict DROPPED --last 10
   # Tìm pods đang cố kết nối database nhưng bị block
   ```

5. So sánh workflow — Hubble vs truyền thống:
   ```bash
   echo "=== Hubble way ==="
   echo "hubble observe --verdict DROPPED → answer in 5s"
   echo ""
   echo "=== Traditional way ==="
   echo "kubectl exec pod -- bash"
   echo "tcpdump -i eth0 port 8080 (cần root, không phải lúc nào cũng có)"
   echo "iptables -L | grep ... (phức tạp, nhiều rules)"
   echo "journalctl | grep felix (chỉ có với Calico)"
   echo "→ 15-30 phút"
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete networkpolicies default-deny allow-frontend-to-backend
kubectl -n production delete pod backend frontend
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Hubble = tcpdump + iptables-L + policy checker trong 1 command:** `hubble observe --verdict DROPPED --follow` thay thế toàn bộ workflow debug cũ — không cần SSH, không cần quyền root, không cần `kubectl exec`.
2. **Ring buffer per node:** Mỗi cilium-agent giữ 4096 events gần nhất → Hubble Relay aggregate từ tất cả nodes → CLI query unified view trên toàn cluster.
3. **Key filter patterns:** `--verdict DROPPED` (security incidents), `--from-pod/--to-pod` (trace specific flow), `--protocol http` (L7 debugging), `--output json | jq` (automation).
4. **Hubble không chỉ debug:** `hubble observe` cho thấy toàn bộ traffic pattern của cluster — "ai đang gọi ai" — network map của production mà không cần document thủ công.
