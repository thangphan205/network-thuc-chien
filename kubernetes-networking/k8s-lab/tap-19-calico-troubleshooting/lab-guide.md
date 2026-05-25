# Lab Tập 19: Troubleshooting Calico — 3 Scenarios

Tập này thực hành workflow debug có hệ thống với 3 scenarios khác nhau.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico đang chạy (từ Tập 9+).
- `calicoctl` đã cài.

---

## 🔬 Thí nghiệm 1: Setup môi trường test

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Deploy client, server và Service:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: client
     labels:
       app: client
   spec:
     nodeName: worker1
     containers:
     - name: c
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: server
     labels:
       app: server
   spec:
     nodeName: worker2
     containers:
     - name: s
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "8080"]
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: server-svc
   spec:
     selector:
       app: server
     ports:
     - port: 8080
       targetPort: 8080
   EOF
   kubectl wait --for=condition=Ready pod/client pod/server --timeout=90s
   SERVER_IP=$(kubectl get pod server -o jsonpath='{.status.podIP}')
   echo "Server IP: $SERVER_IP"
   ```

---

## 💥 Scenario 1: Policy deny không rõ lý do

**Trên `controlplane`:**

1. **Setup broken:** Apply deny policy với ingress rỗng:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: debug-deny
   spec:
     podSelector:
       matchLabels:
         app: server
     policyTypes:
     - Ingress
     ingress: []
   EOF
   ```

2. **Reproduce symptom:**
   ```bash
   kubectl exec client -- nc -zv -w 3 $SERVER_IP 8080
   # (timeout) ← Confirmed
   ```

3. **Debug — Bước 1: Check basics:**
   ```bash
   kubectl get pods -o wide
   # Pod đang Running, đúng node → Pod OK
   ```

4. **Debug — Bước 3: Check policy:**
   ```bash
   kubectl get networkpolicy
   # NAME         POD-SELECTOR   AGE
   # debug-deny   app=server     30s

   kubectl get networkpolicy debug-deny -o yaml | grep -A5 "ingress:"
   # ingress: []  ← Không có rule = deny all!
   ```

5. **Debug — Bước 3: Check iptables:**
   ```bash
   # SSH vào worker2 (nơi server đang chạy)
   # Xem chain cho server endpoint
   ENDPOINT_ID=$(calicoctl get workloadendpoint | grep server | awk '{print $1}')
   echo "Endpoint: $ENDPOINT_ID"
   # multipass exec worker2 -- sudo iptables -L cali-tw-<endpoint-id> -n
   ```

6. **Fix:**
   ```bash
   kubectl delete networkpolicy debug-deny
   kubectl exec client -- nc -zv $SERVER_IP 8080   # ✅ OK ngay
   ```

---

## 💥 Scenario 2: Route bị thiếu tạm thời (BGP mode)

**Trên `controlplane`:**

1. **Setup:** Restart calico-node DaemonSet để simulate route loss:
   ```bash
   kubectl -n calico-system rollout restart daemonset/calico-node
   ```

2. **Trong thời gian restart** — test ngay:
   ```bash
   kubectl exec client -- ping -c 3 -W 2 $SERVER_IP
   # Request timeout ← Route bị xóa trong thời gian restart
   ```

3. **Debug — Bước 2: Check BGP:**
   ```bash
   calicoctl node status
   # STATE: OpenSent (đang reconnect) hoặc Idle
   # ← Chờ ESTABLISHED
   ```

4. **Debug — Bước 2: Check routing table:**
   ```bash
   multipass exec worker1 -- ip route show | grep 10.244
   # (Route đến worker2 subnet có thể vắng mặt tạm thời)
   ```

5. **Watch recovery:**
   ```bash
   watch -n2 'calicoctl node status | grep -E "PEER|STATE"'
   # Sau 10-30 giây: tất cả về ESTABLISHED
   ```

6. **Verify self-healing:**
   ```bash
   kubectl exec client -- ping -c 3 $SERVER_IP
   # OK ✅ — Tự recover không cần can thiệp
   ```

---

## 💥 Scenario 3: Label typo

**Trên `controlplane`:**

1. **Setup:** Apply allow policy:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-client
   spec:
     podSelector:
       matchLabels:
         app: server
     policyTypes:
     - Ingress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: client
       ports:
       - protocol: TCP
         port: 8080
   EOF
   ```

2. **Introduce typo:** Đổi label client thành sai:
   ```bash
   kubectl label pod client app=cliennt --overwrite
   # "cliennt" (2 chữ n)
   ```

3. **Reproduce:**
   ```bash
   kubectl exec client -- nc -zv -w 3 $SERVER_IP 8080
   # (timeout) ← Không có error gì trong kubectl logs
   ```

4. **Debug — Bước 1: Check labels:**
   ```bash
   kubectl get pod client --show-labels
   # LABELS: app=cliennt  ← Typo!

   kubectl get networkpolicy allow-client -o yaml | grep -A3 "matchLabels:"
   # matchLabels:
   #   app: client  ← Policy expect "client" (1 chữ n)
   ```

5. **Fix:**
   ```bash
   kubectl label pod client app=client --overwrite
   kubectl exec client -- nc -zv $SERVER_IP 8080   # ✅ Ngay lập tức
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod client server
kubectl delete svc server-svc
kubectl delete networkpolicy allow-client 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Scenario 1 — Empty ingress:** `ingress: []` khác `ingress:` không có (không có policyType Ingress). Empty ingress = deny all ingress.
2. **Scenario 2 — Self-healing:** BGP routes tự recover sau calico-node restart. Không cần can thiệp — chỉ cần chờ ESTABLISHED.
3. **Scenario 3 — Label typo:** Timeout không có error = nghi ngờ NetworkPolicy. `--show-labels` là lệnh đầu tiên cần chạy.
4. **Workflow 5 bước:** Check basics → BGP → iptables → trace packet → Felix logs. Tuần tự từ trên xuống, không bỏ bước.
