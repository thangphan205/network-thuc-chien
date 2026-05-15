# Lab Tập 11: Migrate từ Flannel sang Calico

Tập này thực hiện migration hoàn chỉnh từ Flannel sang Calico và chứng minh NetworkPolicy bây giờ được enforce thực sự.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Flannel đang chạy (từ Tập 10).
- 3 nodes: `controlplane`, `worker1`, `worker2`.
- Có thể SSH vào tất cả nodes qua `multipass shell`.

---

## 🔬 Thí nghiệm 1: Cleanup Flannel

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Xóa Flannel DaemonSet:
   ```bash
   kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

2. Cleanup network interfaces và configs trên tất cả nodes:
   ```bash
   for NODE in worker1 worker2; do
     multipass exec $NODE -- bash -c '
       sudo ip link del cni0 2>/dev/null || true
       sudo ip link del flannel.1 2>/dev/null || true
       sudo rm -rf /etc/cni/net.d/*
       sudo rm -rf /run/flannel/
     '
   done

   # Trên controlplane cũng cleanup
   sudo ip link del cni0 2>/dev/null || true
   sudo ip link del flannel.1 2>/dev/null || true
   sudo rm -rf /etc/cni/net.d/*
   ```

3. Verify nodes về NotReady (không có CNI):
   ```bash
   kubectl get nodes
   # NAME           STATUS     ROLES
   # controlplane   NotReady   control-plane
   # worker1        NotReady   <none>
   # worker2        NotReady   <none>
   ```

---

## 🚀 Thí nghiệm 2: Cài Calico via Tigera Operator

**Trên `controlplane`:**

1. Cài Tigera Operator:
   ```bash
   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml
   ```

2. Tạo Installation CR với Pod CIDR phù hợp:
   ```bash
   kubectl create -f - <<'EOF'
   apiVersion: operator.tigera.io/v1
   kind: Installation
   metadata:
     name: default
   spec:
     calicoNetwork:
       ipPools:
       - blockSize: 26
         cidr: 10.244.0.0/16
         encapsulation: VXLANCrossSubnet
         natOutgoing: Enabled
         nodeSelector: all()
   EOF
   ```

3. Theo dõi quá trình cài đặt:
   ```bash
   watch kubectl get pods -n calico-system
   # Sau 2-3 phút: tất cả Pods Running
   ```

4. Verify nodes Ready:
   ```bash
   kubectl get nodes
   # NAME           STATUS   ROLES
   # controlplane   Ready    control-plane  ← Calico đang chạy!
   # worker1        Ready    <none>
   # worker2        Ready    <none>
   ```

---

## 💥 Thí nghiệm 3: Verify NetworkPolicy được enforce

**Trên `controlplane`:**

1. Deploy lại pods test:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: database
     labels:
       app: database
   spec:
     nodeName: worker2
     containers:
     - name: db
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "5432"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: frontend
     labels:
       app: frontend
   spec:
     nodeName: worker1
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF
   kubectl wait --for=condition=Ready pod/database pod/frontend --timeout=90s
   ```

2. Test trước khi có NetworkPolicy — vẫn kết nối được:
   ```bash
   DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')
   kubectl exec frontend -- nc -zv $DB_IP 5432
   # Connection to X.X.X.X 5432 port succeeded! ✅ (chưa có policy)
   ```

3. Apply Default Deny:
   ```bash
   kubectl apply -f - <<'EOF'
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
   ```

4. Test lại — **Calico enforce!**
   ```bash
   kubectl exec frontend -- nc -zv $DB_IP 5432
   # (timeout) ← CALICO CHẶN! NetworkPolicy có tác dụng thực sự
   ```

---

## 🔬 Thí nghiệm 4: Kiểm tra iptables chains Felix tạo

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Xem Calico chains trong iptables:
   ```bash
   sudo iptables -L | grep "^Chain cali"
   # Chain cali-FORWARD (1 references)
   # Chain cali-INPUT (1 references)
   # Chain cali-OUTPUT (1 references)
   # Chain cali-from-wl-dispatch
   # Chain cali-to-wl-dispatch
   # Chain cali-fw-<endpoint-id>   ← Per-endpoint egress rules
   # Chain cali-tw-<endpoint-id>   ← Per-endpoint ingress rules
   ```

2. Xem chain cali-FORWARD để thấy policy enforcement:
   ```bash
   sudo iptables -L cali-FORWARD -n --line-numbers
   ```

3. So sánh với Flannel (chỉ kube-proxy rules trước đây):
   ```bash
   # Trước (Flannel): grep "KUBE" → chỉ có kube-proxy rules
   # Giờ (Calico): grep "cali" → có thêm Calico security rules
   sudo iptables -L | grep -c "cali"
   # Nhiều rules → Felix đang enforce policy!
   ```

---

## 🧹 Dọn dẹp (giữ lại cho các tập tiếp theo)

```bash
kubectl delete pod database frontend
kubectl delete networkpolicy default-deny
# Giữ lại Calico — sẽ dùng cho tập 12-20
```

---

## ✅ Tổng kết

1. **Migration 3 bước:** Delete Flannel → Cleanup interfaces → Install Calico Operator + CR.
2. **NetworkPolicy bây giờ thật:** Cùng YAML `podSelector: {}` + `policyTypes: [Ingress, Egress]` → Calico enforce, Flannel bỏ qua.
3. **Felix = bộ não:** Mọi chain `cali-*` trong iptables đều do Felix tạo và quản lý event-driven.
4. **Blast radius giảm đột ngột:** Từ toàn cluster (Flannel) xuống chỉ services được allow (Calico + Default Deny).
