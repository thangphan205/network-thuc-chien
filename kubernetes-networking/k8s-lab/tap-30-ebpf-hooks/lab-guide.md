# Lab Tập 30: 3 Hook Points của eBPF — XDP, TC và sockops

Tập này quan sát BPF programs được Cilium attach tại từng hook point: XDP (trước SKB), TC (ingress/egress trên veth), và sockops (socket layer).

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy trên cluster (từ Tập 27).
- `bpftool` và `tc` có sẵn (trong cilium-agent container và trên host).

---

## 🔬 Thí nghiệm 1: List BPF programs theo hook type

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Xem tất cả BPF programs với type:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -E "^[0-9]+:|type"
   # 23: sched_cls  ← TC programs (ingress/egress trên veth)
   # 24: sched_cls
   # 45: sock_ops   ← sockops program (intercept connect/accept)
   # 46: sk_msg     ← socket message redirect
   # 67: xdp        ← XDP program (nếu NodePort acceleration enabled)
   ```

2. Xem riêng từng loại:
   ```bash
   # Xem TC programs (sched_cls):
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -B1 "sched_cls" | grep "name"
   # name cil_from_container  ← TC ingress (packet VÀO pod)
   # name cil_to_container    ← TC egress (packet RA từ pod)
   # name cil_from_host       ← TC từ host network
   # name cil_to_host         ← TC lên host network

   # Xem sockops programs:
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -B1 "sock_ops\|sk_msg" | grep "name"
   # name bpf_sockops         ← detect same-node, redirect socket
   # name bpf_redir_proxy     ← socket message redirect
   ```

3. Đếm tổng số BPF programs per type:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | awk '{print $2}' | sort | uniq -c | sort -rn
   # 18 sched_cls   ← 1 TC ingress + 1 TC egress per endpoint/interface
   #  2 sock_ops
   #  1 sk_msg
   #  1 xdp
   ```

---

## 🔬 Thí nghiệm 2: Xem TC programs gắn trên veth của Pod

**Trên `controlplane`:**

1. Deploy một test pod và tìm veth interface của nó:
   ```bash
   kubectl run hook-test --image=nicolaka/netshoot -- sleep infinity
   kubectl wait --for=condition=Ready pod/hook-test --timeout=60s

   # Lấy Pod IP để tìm veth tương ứng
   POD_IP=$(kubectl get pod hook-test -o jsonpath='{.status.podIP}')
   echo "Pod IP: $POD_IP"
   ```

2. Tìm veth trên worker node (pod chạy trên node nào):
   ```bash
   NODE=$(kubectl get pod hook-test -o jsonpath='{.spec.nodeName}')
   echo "Pod running on: $NODE"

   # SSH vào node đó và tìm veth
   multipass exec $NODE -- ip link show type veth
   # Tìm veth có ifindex tương ứng với Pod
   # hoặc:
   multipass exec $NODE -- ip route show | grep $POD_IP
   # 10.244.1.5 dev veth3a4b5c6d scope link
   VETH=$(multipass exec $NODE -- ip route show | grep $POD_IP | awk '{print $3}')
   echo "Veth interface: $VETH"
   ```

3. Xem TC qdisc (Cilium thêm `clsact` qdisc):
   ```bash
   multipass exec $NODE -- tc qdisc show dev $VETH
   # qdisc clsact 0: dev veth3a4b5c6d root
   # ← Cilium attach clsact qdisc để có thể gắn TC programs
   ```

4. Xem TC filter (BPF programs) trên ingress và egress:
   ```bash
   # TC ingress: packet VÀO pod (từ ngoài vào)
   multipass exec $NODE -- tc filter show dev $VETH ingress
   # filter protocol all pref 1 bpf chain 0
   # filter protocol all pref 1 bpf ... handle 0x1 cil_from_container [...]

   # TC egress: packet RA từ pod (từ pod ra ngoài)
   multipass exec $NODE -- tc filter show dev $VETH egress
   # filter protocol all pref 1 bpf chain 0
   # filter protocol all pref 1 bpf ... handle 0x1 cil_to_container [...]
   ```

   *Nhận xét:* `cil_from_container` chạy khi pod gửi packet ra (egress của pod = ingress của veth nhìn từ host). Đây là nơi policy enforcement xảy ra.

---

## 🔬 Thí nghiệm 3: Verify sockops program active

**Trên `controlplane`:**

1. Verify sockops BPF program được load:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog show name bpf_sockops
   # 45: sock_ops  name bpf_sockops  tag xxxx  gpl
   #     loaded_at 2024-01-01T00:00:00+0000  uid 0
   #     xlated 2KB  jited 1KB  memlock 4KB
   ```

2. Verify sockops attached vào cgroup (toàn bộ host):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool cgroup show /run/cilium/cgroupv2
   # ID  AttachType  AttachFlags  Name
   # 45  sock_ops    multi        bpf_sockops
   # 46  sk_msg      multi        bpf_redir_proxy
   # ← Attach vào root cgroup → áp dụng cho TẤT CẢ sockets trên node
   ```

3. Xem cilium status để confirm sockops enabled:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium status | grep -i sock
   # Sockops:  Enabled  ← Active
   ```

---

## 💥 Thí nghiệm 4: Quan sát TC program xử lý packet thực tế

**Trên `controlplane`:**

1. Deploy client-server để tạo traffic:
   ```bash
   kubectl run hook-server --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker2"}}' \
     -- nc -lk -p 9090

   SERVER_IP=$(kubectl get pod hook-server -o jsonpath='{.status.podIP}')
   echo "Server IP: $SERVER_IP"
   ```

2. Gửi traffic từ hook-test đến hook-server (cross-node → TC path):
   ```bash
   kubectl exec hook-test -- bash -c "
     for i in \$(seq 1 10); do
       echo 'hello' | nc -w 1 $SERVER_IP 9090 2>/dev/null
       sleep 0.5
     done
     echo 'Done'
   " &
   ```

3. Xem TC drop counter tăng (nếu có NetworkPolicy):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf metrics list | grep -E "Forwarded|dropped|Policy"
   # Forwarded             egress      XXX  → Tăng theo traffic
   # CT: New connection    ingress     YYY  → New connections
   ```

4. So sánh path: apply NetworkPolicy để xem TC DROP:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: deny-hook-server
   spec:
     podSelector:
       matchLabels:
         run: hook-server
     policyTypes:
     - Ingress
     ingress: []
   EOF

   # Test bị block — TC BPF program thực hiện DROP:
   kubectl exec hook-test -- nc -zv -w 2 $SERVER_IP 9090
   # (timeout) ← TC cil_from_container DROP trước khi vào pod

   # Xem drop counter trong metrics:
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf metrics list | grep -i "denied\|drop"
   # Policy denied  ingress  X  ← Tăng

   kubectl delete networkpolicy deny-hook-server
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod hook-test hook-server
```

---

## ✅ Tổng kết

1. **3 hook points, 3 vai trò rõ ràng:** XDP (trước SKB — DDoS/NodePort, tốc độ tối đa), TC (có SKB — policy/NAT/encap, đầy đủ tính năng), sockops (socket layer — same-node bypass, nhanh nhất).
2. **TC dùng `clsact` qdisc:** Cilium thêm `clsact` qdisc vào mỗi veth → gắn `cil_from_container` (ingress) và `cil_to_container` (egress) → policy enforcement xảy ra ở đây cho cross-node traffic.
3. **sockops gắn vào root cgroup:** Áp dụng cho tất cả sockets trên node → intercept mọi `connect()` syscall → detect same-node → redirect mà không cần packet đi qua TC/iptables.
4. **Cilium auto-select:** Agent tự detect topology, tự attach đúng BPF program vào đúng hook — không cần config thủ công, không cần restart để apply thay đổi.
