# Lab Tập 34: Hubble UI — Service Map tự động và DROPPED màu đỏ

Tập này mở Hubble UI, generate traffic patterns, apply policy để tạo RED edges, và thực hành trace incident trực quan qua Service Map.

## 🛠 Yêu cầu chuẩn bị
- Cilium với `hubble.ui.enabled=true` (từ Tập 24).
- Browser có thể mở localhost (hoặc tunnel nếu dùng Multipass).

---

## 🔬 Thí nghiệm 1: Mở Hubble UI

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Verify Hubble UI running:
   ```bash
   kubectl -n kube-system get pods | grep hubble-ui
   # hubble-ui-xxxxx   2/2  Running
   # (2/2: hubble-ui frontend + backend)
   ```

2. Port-forward Hubble UI:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-ui 12000:80 &
   echo "Hubble UI: http://localhost:12000"
   ```

3. Nếu dùng Multipass — cần tunnel từ macOS:
   ```bash
   # Lấy IP của controlplane
   MASTER_IP=$(multipass info controlplane | grep IPv4 | awk '{print $2}')
   echo "controlplane IP: $MASTER_IP"

   # Trên macOS (terminal mới):
   # ssh -L 12000:localhost:12000 ubuntu@$MASTER_IP
   # Hoặc port-forward trực tiếp từ macOS nếu có kubeconfig setup
   ```

4. Mở browser: `http://localhost:12000`
   - Chọn namespace `production` từ dropdown (sẽ có sau khi deploy ở thí nghiệm 2)
   - Lúc này Service Map trống — chưa có traffic

---

## 🔬 Thí nghiệm 2: Deploy 3-tier stack và generate traffic

**Trên `controlplane`:**

1. Deploy frontend, backend, database:
   ```bash
   kubectl create namespace production 2>/dev/null || true

   kubectl apply -n production -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: frontend
     labels:
       app: frontend
       tier: web
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: backend
     labels:
       app: backend
       tier: api
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "8080"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: database
     labels:
       app: database
       tier: data
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "5432"]
   EOF

   kubectl -n production wait --for=condition=Ready \
     pod/frontend pod/backend pod/database --timeout=90s

   BACKEND_IP=$(kubectl -n production get pod backend \
     -o jsonpath='{.status.podIP}')
   DB_IP=$(kubectl -n production get pod database \
     -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   echo "Database IP: $DB_IP"
   ```

2. Generate traffic — frontend → backend (normal):
   ```bash
   kubectl -n production exec frontend -- bash -c "
     while true; do
       nc -zv $BACKEND_IP 8080 &>/dev/null
       sleep 0.3
     done
   " &
   FRONTEND_BG=$!
   echo "Traffic generator running (PID: $FRONTEND_BG)"
   ```

3. Xem Hubble UI — Refresh browser sau 10 giây:
   ```
   Service Map sẽ hiển thị:
   [frontend] ──GREEN──▶ [backend]
   ```

---

## 💥 Thí nghiệm 3: Tạo RED edge — block frontend → database

**Trên `controlplane`:**

1. Apply policy chỉ allow backend → database, block frontend → database:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: protect-database
   spec:
     podSelector:
       matchLabels:
         app: database
     policyTypes: [Ingress]
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: backend
       ports:
       - {protocol: TCP, port: 5432}
   EOF
   ```

2. Simulate frontend cố kết nối database trực tiếp (sẽ bị drop):
   ```bash
   kubectl -n production exec frontend -- bash -c "
     while true; do
       nc -zv -w 1 $DB_IP 5432 &>/dev/null
       sleep 0.5
     done
   " &
   FRONTEND_DB_BG=$!
   ```

3. Xem Hubble UI — Refresh browser:
   ```
   Service Map sẽ hiển thị:
   [frontend] ──GREEN──▶ [backend]        ← OK
       │
       └──RED──▶ [database]               ← DROPPED!
   
   Edge màu đỏ = frontend đang bị block khi cố connect database
   ```

---

## 🔬 Thí nghiệm 4: Click và trace incident trong UI

**Trong Hubble UI browser:**

1. Click vào **RED edge** giữa frontend và database:
   ```
   Flow List xuất hiện phía dưới:
   TIMESTAMP     SOURCE              DEST              VERDICT   REASON
   14:23:05.123  production/frontend production/database:5432  DROPPED  Policy denied
   14:23:05.623  production/frontend production/database:5432  DROPPED  Policy denied
   ...
   ```

2. Click vào một flow để xem detail:
   ```
   Source: production/frontend (10.244.1.5)
   Destination: production/database:5432 (10.244.1.7)
   Protocol: TCP
   Verdict: DROPPED
   Drop reason: Policy denied
   Timestamp: 2026-05-15T14:23:05.123Z
   ```

3. Click vào **GREEN edge** (frontend → backend) để xem FORWARDED flows:
   ```
   Source: production/frontend
   Destination: production/backend:8080
   Verdict: FORWARDED
   Packets: 142 flows in last minute
   ```

4. Dùng filter bar để focus:
   ```
   Namespace: production
   Verdict: Dropped
   → Chỉ thấy RED flows
   ```

5. Fix policy và watch edge turn GREEN:
   ```bash
   # Không fix thực sự — đây là intended policy
   # Để demo: delete policy → frontend → database trở lại FORWARDED
   kubectl -n production delete networkpolicy protect-database

   # Hubble UI: RED edge biến mất → GREEN (hoặc biến mất nếu không còn traffic)
   ```

---

## 🧹 Dọn dẹp

```bash
kill $FRONTEND_BG $FRONTEND_DB_BG 2>/dev/null || true
kubectl -n production delete networkpolicies --all
kubectl -n production delete pod frontend backend database
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Service Map zero-config:** Hubble UI tự vẽ topology từ observed traffic — không cần maintain diagram thủ công. Mỗi khi có service mới, edge mới xuất hiện tự động.
2. **RED edges = immediate action:** Edge đỏ chỉ ra có traffic đang bị drop. Click → xem flows → identify policy vi phạm. Không cần biết trước "cần check policy nào".
3. **UI vs CLI:** CLI (`hubble observe`) tốt cho scripting và quick query. UI tốt cho architecture review, onboarding, và incident postmortem — visual context giúp hiểu nhanh hơn text log.
4. **Real-time feedback:** Fix policy → Hubble UI cập nhật trong vòng 15 giây → edge GREEN. Workflow: thấy RED → fix → verify GREEN ngay trong UI, không cần chạy lại tests.
