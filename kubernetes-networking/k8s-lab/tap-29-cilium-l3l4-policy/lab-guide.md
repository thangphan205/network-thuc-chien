# Lab Tập 29: L3/L4 Policy trong Cilium — K8s NetworkPolicy vs CiliumNetworkPolicy

Tập này áp dụng cả K8s NetworkPolicy lẫn CiliumNetworkPolicy, verify Cilium compile sang BPF thay vì iptables, và dùng entity selector để allow/deny traffic.

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy trên cluster (từ Tập 24).
- Hubble Relay running (`kubectl -n kube-system get pods | grep hubble-relay`).
- `hubble` CLI đã cài (hoặc dùng port-forward để query).

---

## 🔬 Thực nghiệm 1: Deploy và verify K8s NetworkPolicy qua Cilium

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

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
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: external-client
     labels:
       app: external
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF

   kubectl -n production wait --for=condition=Ready \
     pod/backend pod/frontend pod/external-client --timeout=60s
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   echo "Backend IP: $BACKEND_IP"
   ```

2. Apply K8s NetworkPolicy (standard):
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-frontend-only
   spec:
     podSelector:
       matchLabels:
         app: backend
     policyTypes:
     - Ingress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: frontend
       ports:
       - protocol: TCP
         port: 8080
   EOF
   ```

3. Verify Cilium compile policy (không dùng iptables):
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1)

   # Verify không có iptables rules liên quan
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     iptables -L | grep -i "backend\|frontend" | wc -l
   # 0 ← Cilium không dùng iptables cho policy!

   # Verify policy trong BPF map
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf policy list | head -10
   # Thấy rules từ policy vừa apply
   ```

4. Test policy:
   ```bash
   # Frontend → backend: ALLOWED
   kubectl -n production exec frontend -- nc -zv -w 3 $BACKEND_IP 8080
   # Connection succeeded ✅

   # External-client → backend: BLOCKED
   kubectl -n production exec external-client -- nc -zv -w 3 $BACKEND_IP 8080
   # (timeout) ✅
   ```

---

## 🔬 Thực nghiệm 2: CiliumNetworkPolicy với fromEntities

**Trên `controlplane`:**

1. Delete K8s NetworkPolicy, thay bằng CiliumNetworkPolicy:
   ```bash
   kubectl -n production delete networkpolicy allow-frontend-only

   kubectl apply -n production -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: backend-entity-policy
   spec:
     endpointSelector:
       matchLabels:
         app: backend
     ingress:
     - fromEndpoints:
       - matchLabels:
           app: frontend
       toPorts:
       - ports:
         - port: "8080"
           protocol: TCP
     - fromEntities:
       - "host"       # Allow từ Node host network (health checks, monitoring)
   EOF
   ```

2. Verify CiliumNetworkPolicy được tạo:
   ```bash
   kubectl -n production get ciliumnetworkpolicies
   # NAME                    AGE
   # backend-entity-policy   5s
   ```

3. Test với entity selector:
   ```bash
   # Frontend (Pod label match) → ALLOWED
   kubectl -n production exec frontend -- nc -zv -w 3 $BACKEND_IP 8080
   # Connection succeeded ✅

   # External-client (không match) → BLOCKED
   kubectl -n production exec external-client -- nc -zv -w 3 $BACKEND_IP 8080
   # (timeout) ✅

   # Host network (entity "host") → ALLOWED
   # Simulate từ host: ping từ worker node
   BACKEND_NODE=$(kubectl -n production get pod backend -o jsonpath='{.spec.nodeName}')
   multipass exec $BACKEND_NODE -- nc -zv -w 3 $BACKEND_IP 8080
   # Connection succeeded ✅ ← host entity allowed
   ```

---

## 🔬 Thực nghiệm 3: CIDR-based ingress policy

**Trên `controlplane`:**

1. Apply CiliumNetworkPolicy với CIDR:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: backend-cidr-policy
   spec:
     endpointSelector:
       matchLabels:
         app: backend
     ingress:
     - fromCIDR:
       - "192.168.64.0/24"   # Multipass network — allow monitoring từ host
     - fromEndpoints:
       - matchLabels:
           app: frontend
       toPorts:
       - ports:
         - port: "8080"
           protocol: TCP
   EOF
   ```

2. Xem policy đang apply:
   ```bash
   kubectl -n production get ciliumnetworkpolicies
   # Cả 2 policies: backend-entity-policy, backend-cidr-policy
   # → Union logic: cả hai đều áp dụng (additive)
   ```

3. Verify CIDR hoạt động:
   ```bash
   # Lấy IP của controlplane (192.168.64.x)
   HOST_IP=$(multipass info controlplane | grep IPv4 | awk '{print $2}')
   echo "Host IP: $HOST_IP"

   # Từ controlplane → backend: ALLOWED (CIDR match)
   nc -zv -w 3 $BACKEND_IP 8080
   # Connection succeeded ✅ ← CIDR 192.168.64.0/24 match
   ```

---

## 🔬 Thực nghiệm 4: Xem Hubble flows khi policy block

**Trên `controlplane`:**

1. Port-forward Hubble Relay:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2
   hubble status
   # Healthcheck: Ok
   ```

2. Watch DROPPED flows:
   ```bash
   hubble observe --namespace production \
     --verdict DROPPED --follow &
   HUBBLE_PID=$!
   ```

3. Generate blocked traffic:
   ```bash
   kubectl -n production exec external-client -- \
     nc -zv -w 2 $BACKEND_IP 8080 &>/dev/null || true
   kubectl -n production exec external-client -- \
     nc -zv -w 2 $BACKEND_IP 8080 &>/dev/null || true
   sleep 2

   # Hubble output:
   # production/external-client → production/backend:8080  DROPPED  Policy denied
   ```

4. Watch FORWARDED flows:
   ```bash
   kill $HUBBLE_PID 2>/dev/null
   hubble observe --namespace production \
     --from-pod production/frontend \
     --to-pod production/backend \
     --verdict FORWARDED &

   kubectl -n production exec frontend -- nc -zv -w 3 $BACKEND_IP 8080

   # Hubble: production/frontend → production/backend:8080  FORWARDED ✅
   kill %% 2>/dev/null
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete ciliumnetworkpolicies --all
kubectl -n production delete pod backend frontend external-client
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Backward compatible:** K8s NetworkPolicy chạy trên Cilium không cần sửa — Cilium compile sang BPF map, không dùng iptables. Verify bằng `iptables -L | grep backend` → 0 rules.
2. **CiliumNetworkPolicy extensions:** `fromEntities` (cluster/host/world), `fromCIDR` (ingress và egress), `icmps` (ICMP type filtering) — features Calico/K8s NetworkPolicy không có.
3. **Entity "host":** Allow traffic từ Node host network namespace — hữu ích cho health checks, monitoring agents chạy trên Node mà không phải trong Pod.
4. **Union logic (giống Calico):** Nhiều CiliumNetworkPolicy trên cùng endpoint = additive (tất cả áp dụng). Hubble observe cho thấy ngay policy nào đang block.
