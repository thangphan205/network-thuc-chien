# Lab Tập 38: Cilium Lab 1 — Pod label sai, Hubble show "Policy denied" ngay lập tức

Tập này thực hành debug scenario giống Tập 20 (Calico) nhưng với Cilium + Hubble: developer deploy backend-v2 quên label, frontend timeout, Hubble chỉ ra root cause trong 30 giây.

## 🛠 Yêu cầu chuẩn bị
- Cilium + Hubble đang chạy (từ Tập 25).
- Cluster 3 nodes (controlplane, worker1, worker2).

---

## 🔬 Thí nghiệm 1: Setup môi trường production với policy

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Tạo namespace và apply policies:
   ```bash
   kubectl create namespace production 2>/dev/null || true

   # Default deny ingress
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny
   spec:
     podSelector: {}
     policyTypes: [Ingress]
   EOF

   # Allow: chỉ frontend → backend (app=backend)
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

2. Deploy backend-v2 **KHÔNG có label** (bug) và frontend (đủ label):
   ```bash
   # backend-v2: thiếu label app=backend
   kubectl run backend-v2 -n production \
     --image=nicolaka/netshoot \
     -- nc -lk -p 8080

   # frontend: đủ label
   kubectl run frontend -n production \
     --image=nicolaka/netshoot \
     --labels="app=frontend" \
     -- sleep infinity

   kubectl -n production wait --for=condition=Ready \
     pod/backend-v2 pod/frontend --timeout=60s
   ```

3. Lấy IP và verify labels:
   ```bash
   BACKEND_IP=$(kubectl -n production get pod backend-v2 \
     -o jsonpath='{.status.podIP}')
   echo "backend-v2 IP: $BACKEND_IP"

   # Confirm: backend-v2 không có label
   kubectl -n production get pod --show-labels
   # NAME         LABELS
   # backend-v2   <none>   ← Đây là bug!
   # frontend     app=frontend
   ```

---

## 🔬 Thí nghiệm 2: Debug với Hubble — 30 giây tìm root cause

**Trên `controlplane`:**

1. Setup Hubble observer **trước** khi trigger vấn đề:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2

   # Start observer — watch DROPPED flows
   hubble observe --namespace production \
     --verdict DROPPED --follow &
   HUBBLE_PID=$!
   ```

2. Trigger connection từ frontend → backend-v2:
   ```bash
   kubectl -n production exec frontend -- \
     nc -zv -w 3 $BACKEND_IP 8080 &>/dev/null || true
   
   sleep 2
   ```

3. Đọc Hubble output:
   ```
   Hubble output ngay lập tức:
   production/frontend → production/backend-v2:8080
   DROPPED  Policy denied
   
   → Không cần: kubectl logs, tcpdump, iptables -L
   → Root cause rõ ràng: Policy denied!
   ```

4. So sánh với Calico (Tập 20):
   ```
   Calico:
     kubectl get pod --show-labels → xem labels
     kubectl get networkpolicy → đọc selector
     iptables -L cali-tw-* → tìm rule (cần root)
     Infer: "à, thiếu label" → 5-15 phút

   Cilium + Hubble:
     hubble observe --verdict DROPPED
     → "Policy denied" xuất hiện ngay → 30 giây
   ```

---

## 💥 Thí nghiệm 3: Xác nhận root cause qua Cilium identity

**Trên `controlplane`:**

1. Xem labels của backend-v2:
   ```bash
   kubectl -n production get pod backend-v2 --show-labels
   # NAME        LABELS
   # backend-v2  <none>   ← Không có label!
   
   # Policy yêu cầu: matchLabels {app: backend}
   # backend-v2 không match → không được policy protect
   # → default deny áp dụng → mọi ingress bị DROP
   ```

2. Verify qua Cilium endpoint list:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium endpoint list | grep -E "ENDPOINT|backend-v2|frontend"
   # ENDPOINT  POLICY (ingress)  IDENTITY  POD NAME
   # 1234      Enabled           12345     frontend
   # 2345      Enabled           99999     backend-v2
   #                             ^^^^^
   # Identity 99999 = "unlabeled" reserved identity!
   # Policy allow rule: identity 12345 (frontend) → port 8080
   # Lookup: src=12345 → dst=backend-v2(unlabeled) → NO MATCH → DROP
   ```

3. Hiểu Cilium Identity model:
   ```
   Cilium Identity = hash(Pod labels)

   backend-v2 không có label:
     Labels: {}  →  Identity: 99999 (reserved: "unlabeled")

   frontend có label app=frontend:
     Labels: {app: frontend}  →  Identity: 12345

   Policy allow-frontend-to-backend:
     Allow: fromEndpoints {app: backend}  (identity 7891)
     Khi frontend → backend-v2:
       src_identity = 12345
       dst = backend-v2 → unlabeled (99999), không match {app: backend}
       → DROP: Policy denied
   ```

---

## 🔬 Thí nghiệm 4: Fix label và verify với Hubble realtime

**Trên `controlplane`:**

1. Fix: thêm label cho backend-v2:
   ```bash
   kubectl -n production label pod backend-v2 app=backend
   # pod/backend-v2 labeled

   # Verify label đã add:
   kubectl -n production get pod backend-v2 --show-labels
   # NAME        LABELS
   # backend-v2  app=backend   ← Fixed!
   ```

2. Verify Hubble thấy FORWARDED ngay (không cần restart):
   ```bash
   # Test connection lại
   kubectl -n production exec frontend -- \
     nc -zv -w 3 $BACKEND_IP 8080

   sleep 2
   # Hubble output bây giờ:
   # production/frontend → production/backend-v2:8080
   # FORWARDED   ← Thay đổi tức thì!
   ```

3. Verify Cilium identity thay đổi:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium endpoint list | grep backend-v2
   # ENDPOINT  POLICY (ingress)  IDENTITY  POD NAME
   # 2345      Enabled           7891      backend-v2
   #                             ^^^^
   # Identity thay đổi từ 99999 → 7891
   # 7891 = hash({app: backend}) → match policy → ALLOW
   ```

4. Tắt Hubble observer và dọn dẹp:
   ```bash
   kill $HUBBLE_PID 2>/dev/null
   pkill -f "port-forward" 2>/dev/null || true
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete networkpolicies --all
kubectl -n production delete pod backend-v2 frontend
```

---

## ✅ Tổng kết

1. **Hubble = instant root cause:** `hubble observe --verdict DROPPED` show "Policy denied" trong vòng giây — không cần infer từ iptables chains như Calico. Debug time: 30-60 giây vs 5-15 phút.
2. **Cilium Identity model:** Identity = `hash(Pod labels)`. Thêm/bớt label → identity thay đổi ngay → BPF policy map lookup kết quả thay đổi → không cần restart Pod hay Cilium agent.
3. **Debug workflow chuẩn:** `hubble observe --verdict DROPPED` → đọc reason → "Policy denied" → `kubectl get pod --show-labels` → tìm label mismatch → `kubectl label pod` → Hubble xác nhận FORWARDED.
4. **`cilium endpoint list` xác nhận identity:** Endpoint có identity `99999` (unlabeled) = không có label → sẽ không match bất kỳ policy nào có `matchLabels` — đây là dấu hiệu chắc chắn của bug label missing.
