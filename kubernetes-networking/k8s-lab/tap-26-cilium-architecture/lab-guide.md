# Lab Tập 26: Kiến trúc Cilium — Operator, Agent, GoBGP, Hubble

Tập này khám phá từng component Cilium, so sánh với Calico, và verify Identity model (label hash → numeric ID).

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy trên cluster (từ Tập 24).
- Ít nhất 1 Pod đang chạy để xem endpoints và identities.

---

## 🔬 Thí nghiệm 1: Xem tất cả Cilium components

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Xem Cilium Agent pods (DaemonSet — 1 per node):
   ```bash
   kubectl -n kube-system get pods -l k8s-app=cilium -o wide
   # NAME            READY   STATUS    NODE
   # cilium-xxxxx    1/1     Running   controlplane
   # cilium-yyyyy    1/1     Running   worker1
   # cilium-zzzzz    1/1     Running   worker2
   ```

2. Xem Cilium Operator (1 instance per cluster):
   ```bash
   kubectl -n kube-system get pods -l name=cilium-operator
   # cilium-operator-xxxxx  1/1  Running  controlplane
   ```

3. Xem Hubble Relay (nếu enabled):
   ```bash
   kubectl -n kube-system get pods -l k8s-app=hubble-relay
   # hubble-relay-xxxxx  1/1  Running
   ```

4. Xem Cilium status tổng quan từ bên trong agent:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- cilium status
   # KVStore:     Ok   Disabled (Cilium dùng K8s CRDs, không cần etcd riêng)
   # Kubernetes:  Ok   1.29 (v1.29.x)
   # Cilium:      Ok   1.15.x
   # NodeMonitor: Disabled
   # Hubble:      Ok   Current/Max Flows: 4096/4096
   # BPF:         Ok
   # Sockops:     Enabled
   ```

   *Nhận xét:* `KVStore: Disabled` — Calico cần etcd riêng hoặc Kubernetes API, Cilium chỉ cần K8s CRDs.

---

## 🔬 Thí nghiệm 2: Inspect Endpoints và Identities

**Trên `controlplane`:**

1. Deploy test pods với labels rõ ràng:
   ```bash
   kubectl run frontend --image=nicolaka/netshoot \
     --labels="app=frontend,env=prod" -- sleep infinity
   kubectl run backend --image=nicolaka/netshoot \
     --labels="app=backend,env=prod" -- sleep infinity
   kubectl wait --for=condition=Ready pod/frontend pod/backend --timeout=60s
   ```

2. Xem endpoints Cilium đang manage:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list
   # ENDPOINT  POLICY (ingress)  POLICY (egress)  IDENTITY  IPv4
   # 1234      Disabled          Disabled          7891      10.244.1.5
   # 2345      Disabled          Disabled          12345     10.244.1.8
   # ← Mỗi Pod có IDENTITY (numeric) không phải chỉ IP
   ```

3. Xem identity mapping (label → numeric ID):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium identity list
   # IDENTITY  LABELS
   # 7891      k8s:app=frontend;k8s:env=prod;k8s:io.kubernetes.pod.namespace=default
   # 12345     k8s:app=backend;k8s:env=prod;k8s:io.kubernetes.pod.namespace=default
   # 1         reserved:host
   # 2         reserved:world
   ```

4. Xem BPF endpoint map (local endpoints — dùng cho sockops):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf endpoint list
   # ENDPOINT  FLAGS  IPv4        MAC
   # 1234      0x0    10.244.1.5  xx:xx:xx:xx:xx:xx
   # ← Chỉ Pods trên node hiện tại — đây là cilium_lxc map
   ```

---

## 💥 Thí nghiệm 3: Verify Identity persist khi Pod restart

**Trên `controlplane`:**

1. Ghi lại identity của frontend pod hiện tại:
   ```bash
   OLD_IP=$(kubectl get pod frontend -o jsonpath='{.status.podIP}')
   echo "Frontend IP trước restart: $OLD_IP"

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list | grep $OLD_IP
   # ENDPOINT  ...  IDENTITY  IPv4
   # 1234      ...  7891      10.244.1.5
   FRONTEND_IDENTITY=7891  # ghi lại
   ```

2. Delete và recreate frontend pod (simulate restart):
   ```bash
   kubectl delete pod frontend
   kubectl run frontend --image=nicolaka/netshoot \
     --labels="app=frontend,env=prod" -- sleep infinity
   kubectl wait --for=condition=Ready pod/frontend --timeout=60s
   ```

3. Verify IP thay đổi nhưng Identity giữ nguyên:
   ```bash
   NEW_IP=$(kubectl get pod frontend -o jsonpath='{.status.podIP}')
   echo "Frontend IP sau restart: $NEW_IP"
   # ← IP thay đổi!

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list | grep frontend
   # ENDPOINT  ...  IDENTITY  IPv4
   # 5678      ...  7891      10.244.1.9  ← IP mới, IDENTITY vẫn 7891!
   ```

   *Nhận xét:* Identity = hash của labels → labels không đổi → identity không đổi → policy tự apply cho Pod mới mà không cần converge.

---

## 🔬 Thí nghiệm 4: So sánh Architecture với Calico

**Trên `controlplane`:**

1. Kiểm tra Cilium Agent logs (equivalent của Felix logs):
   ```bash
   kubectl -n kube-system logs $CILIUM_POD --tail=20 | grep -i "policy\|endpoint\|identity"
   # level=info msg="Regenerating endpoints in parallel"
   # level=info msg="Successfully regenerated BPF programs"
   ```

2. Verify Cilium không cần etcd riêng (dùng K8s CRDs):
   ```bash
   kubectl get crds | grep cilium | head -10
   # ciliumclusterwidenetworkpolicies.cilium.io
   # ciliumendpoints.cilium.io
   # ciliumidentities.cilium.io
   # ciliumnetworkpolicies.cilium.io
   # ciliumnodes.cilium.io
   # ← Tất cả state trong K8s CRDs — không cần datastore riêng
   ```

3. Xem Cilium node state (equivalent của `calicoctl node status`):
   ```bash
   kubectl get ciliumnodes
   # NAME           CILIUMINTERNALIP  INTERNALIP       AGE
   # controlplane   10.244.0.1        192.168.64.10    2d
   # worker1        10.244.1.1        192.168.64.11    2d
   # worker2        10.244.2.1        192.168.64.12    2d
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod frontend backend
```

---

## ✅ Tổng kết

1. **cilium-agent = Felix + BIRD + Typha trong 1 process:** Policy engine, BGP speaker (GoBGP), IPAM, và Hubble observer đều trong cùng DaemonSet container — ít moving parts hơn Calico.
2. **Cilium Operator ≠ Tigera Operator:** Operator quản lý CRDs và IPAM allocation cluster-wide. Tigera Operator quản lý cài đặt/upgrade Calico stack — vai trò khác.
3. **Identity model giải quyết IP churn problem:** Pod restart → IP mới nhưng labels giữ nguyên → identity (numeric hash) giữ nguyên → policy không bị "miss" trong khoảng thời gian converge.
4. **K8s CRDs thay datastore:** `ciliumendpoints`, `ciliumidentities`, `ciliumnodes` — tất cả state trong K8s API, không cần etcd riêng hay Typha proxy.
