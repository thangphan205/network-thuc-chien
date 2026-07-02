# Lab Tập 35: Troubleshooting Cilium — cilium status → hubble observe → cilium CLI

Tập này thực hành toàn bộ 5-level troubleshooting workflow của Cilium, từ health check đến policy debugging đến node connectivity.

## 🛠 Yêu cầu chuẩn bị
- Cilium + Hubble đang chạy (từ Tập 23).
- Cluster 3 nodes (controlplane, worker1, worker2).

---

## 🔬 Thực nghiệm 1: Level 1 — cilium status health check

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Lấy cilium-agent pod và chạy health check:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium -o name | head -1)
   echo "Cilium pod: $CILIUM_POD"

   kubectl -n kube-system exec -it $CILIUM_POD -- cilium status
   ```

2. Đọc từng indicator:
   ```bash
   # Chạy và grep từng phần quan trọng:
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium status | grep -E "Kubernetes:|Cilium:|IPAM:|Unreachable"

   # Expected output:
   # Kubernetes:         Ok   1.29+ (v1.29.x)
   # Cilium:             Ok   1.19.5 (v1.19.5-xxxxxxx)
   # IPAM:               IPv4: x/254 allocated
   # Unreachable nodes:  0   ← QUAN TRỌNG: phải là 0
   ```
   > **💡 Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** không có field `BPF:`/`Sockops:` đứng riêng trong `cilium status` (không tồn tại trong formatter thật). Field `BPF Maps: dynamic sizing` chỉ hiện với `--verbose`/`--all-*`. Field thay `Sockops` cũ là `Socket LB` — cũng chỉ hiện với `--verbose`, trong khối `KubeProxyReplacement Details`:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium status --verbose | grep -E "BPF Maps:|Socket LB:"
   # BPF Maps:    dynamic sizing: true
   # Socket LB:   Enabled
   ```

3. Xem tất cả Cilium agent pods health:
   ```bash
   # Kiểm tra tất cả 3 nodes:
   for NODE in controlplane worker1 worker2; do
     POD=$(kubectl -n kube-system get pod \
       -l k8s-app=cilium \
       --field-selector spec.nodeName=$NODE \
       -o name | head -1)
     echo "=== $NODE ($POD) ==="
     kubectl -n kube-system exec -it $POD -- \
       cilium status 2>/dev/null | grep -E "Cilium:|Unreachable"
   done
   ```

---

## 🔬 Thực nghiệm 2: Level 2 — hubble observe flow debugging

**Trên `controlplane`:**

1. Deploy test pods và inject bug:
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

   # Default deny — simulate production
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

2. Setup Hubble và observe drops:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2

   hubble observe --namespace production \
     --verdict DROPPED --follow &
   HUBBLE_PID=$!
   ```

3. Trigger connection và xem Hubble output:
   ```bash
   kubectl -n production exec frontend -- \
     nc -zv -w 3 $BACKEND_IP 8080 &>/dev/null || true

   sleep 2
   # Hubble output:
   # production/frontend → production/backend:8080  DROPPED  Policy denied

   kill $HUBBLE_PID 2>/dev/null
   ```

---

## 🔬 Thực nghiệm 3: Level 3 — Policy debugging với cilium CLI

**Trên `controlplane`:**

1. Xem endpoint list và policy enforcement status:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list
   # ENDPOINT  POLICY (ingress)  POLICY (egress)  IDENTITY  IPv6   IPv4         STATUS
   # 1234      Enabled           Enabled           7891             10.244.1.5   ready
   # 5678      Enabled           Enabled           12345            10.244.1.8   ready
   ```
   > **💡 Lưu ý:** Cột thật không có "POD NAME" riêng — tên pod chỉ suy ra được gián tiếp qua nhãn trong cột `LABELS` (`k8s:app=backend`...) khi chạy full output không rút gọn, hoặc đối chiếu `IPv4` với `kubectl get pod -o wide`.

2. Xem BPF policy map cho backend endpoint:
   ```bash
   # Lấy endpoint ID của backend
   BACKEND_EP=$(kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list | grep "backend" | awk '{print $1}' | head -1)
   echo "Backend endpoint ID: $BACKEND_EP"

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf policy get $BACKEND_EP
   # (no entries)
   ```
   > **💡 Lưu ý:** `cilium bpf policy list` KHÔNG nhận argument endpoint — subcommand đúng để xem policy map của 1 endpoint cụ thể là `cilium bpf policy get <endpoint-id>`. Map policy chỉ là **allow-list**: default-deny ngầm định (không có entry = drop), nên khi chưa có allow rule nào thì map **rỗng** — không có dòng "Deny" tường minh nào được ghi (`Deny` không phải verdict thật sự xuất hiện trong output).

3. Add allow policy và verify policy map update:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-frontend
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

   # Verify policy map updated (trong vòng vài giây):
   sleep 2
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf policy get $BACKEND_EP
   # POLICY  DIRECTION  LABELS (source:key[=value])  PORT/PROTO  PROXY PORT  BYTES  PACKETS
   # Allow   Ingress    k8s:app=frontend              8080/TCP    NONE        0      0
   # ← frontend identity được thêm! Map chỉ liệt kê rule Allow (default-deny ngầm định, không có dòng Deny).
   ```

---

## 🔬 Thực nghiệm 4: Level 4 & 5 — BPF và Node connectivity

**Trên `controlplane`:**

1. Verify BPF programs loaded (Level 4):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -E "^[0-9]+:" | head -10
   # Xem có sched_cls (TC), cgroup_sock_addr (Socket LB) programs không

   # Đếm TC programs (thường 2 per endpoint)
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep "sched_cls" | wc -l
   # Số lớn hơn 0 = BPF loaded OK

   # Verify conntrack (có connections active không)
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf ct list global | wc -l
   ```

2. Xem node-to-node connectivity (Level 5):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium-health status
   # Nodes:
   #   controlplane (localhost):
   #     Host connectivity:     Ok   Xms
   #     Endpoint connectivity: Ok   Xms
   #   worker1:
   #     Host connectivity:     Ok   Xms
   #     Endpoint connectivity: Ok   Xms
   #   worker2:
   #     Host connectivity:     Ok   Xms
   #     Endpoint connectivity: Ok   Xms
   # ← Tất cả OK = cluster healthy
   ```

3. Quick connectivity test (Cilium built-in):

   > **⚠️ Lưu ý:** `cilium connectivity test` là tính năng của `cilium-cli` — 1 binary chạy **ngoài cluster** (không nằm trong cilium-agent container, không tồn tại qua `kubectl exec` dù gọi tên `cilium` hay `cilium-dbg`). Nó tự deploy test pods/services riêng và chạy từ máy có kubeconfig, không phải lệnh debug nội bộ agent. Muốn dùng, cài `cilium-cli` trên `controlplane` (đã hướng dẫn ở Tập 23) rồi chạy trực tiếp, không qua `kubectl exec`:
   ```bash
   # Cài cilium-cli nếu chưa có (xem Tập 23), rồi chạy trực tiếp trên controlplane:
   cilium connectivity test --test pod-to-pod || \
     echo "Note: Full connectivity test cần thêm setup (image pull, RBAC...)"

   # Alternative — manual cross-node ping (không cần cilium-cli):
   kubectl -n production exec frontend -- \
     ping -c 3 $BACKEND_IP
   # 3 packets transmitted, 3 received ← Cross-node connectivity OK
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl -n production delete networkpolicies --all
kubectl -n production delete pod backend frontend
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **5-level hierarchy:** Start từ Level 1 (health) → move down chỉ khi cần. Hầu hết incidents resolve ở Level 2 (Hubble) hoặc Level 3 (policy map).
2. **`cilium status` chỉ số quan trọng:** `Unreachable nodes: 0` (network OK), `BPF Maps: dynamic sizing` (`--verbose`, kernel BPF OK), `Socket LB: Enabled` (`--verbose`, thay cho `Sockops` cũ — performance optimization active).
3. **Hubble drop reasons:** `"Policy denied"` → Label/policy issue. `"MTU exceeded"` → MTU misconfiguration. `"No route"` → Routing issue. Không cần infer như Calico.
4. **`cilium bpf policy get <endpoint-id>`:** Xem BPF policy map entries trực tiếp — verify policy đã converge chưa (quan trọng hơn kubectl get networkpolicy vì đó là desired state, không phải actual enforcement).
