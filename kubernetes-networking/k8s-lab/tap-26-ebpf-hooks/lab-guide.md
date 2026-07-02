# Lab Tập 26: 3 Hook Points của eBPF — XDP, TC và Cgroup/Socket hooks

Tập này quan sát BPF programs được Cilium attach tại từng hook point: XDP (trước SKB), TC (ingress/egress trên veth), và cgroup/socket hooks (socket layer — connect/sendmsg/recvmsg). Lưu ý: tính năng `sockops`/`sk_msg` (TCP splice cũ) đã bị Cilium loại bỏ từ v1.14 — cơ chế socket-layer hiện tại dùng `BPF_PROG_TYPE_CGROUP_SOCK_ADDR` (xem Thực nghiệm 3).

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy trên cluster (từ Tập 23).
- `bpftool` và `tc` có sẵn (trong cilium-agent container và trên host).

---

## 🔬 Thực nghiệm 1: List BPF programs theo hook type

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Xem tất cả BPF programs với type:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -E "^[0-9]+:"
   # 23: sched_cls        ← TC programs (ingress/egress trên veth)
   # 24: sched_cls
   # 45: cgroup_sock_addr ← socket hook (connect/sendmsg/recvmsg — Socket LB)
   # 46: cgroup_sock_addr
   # 67: xdp              ← XDP program (nếu NodePort acceleration enabled)
   ```

2. Xem riêng từng loại:
   ```bash
   # Xem TC programs (sched_cls):
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -B1 "sched_cls" | grep "name"
   # name cil_from_container  ← TC ingress (packet RA từ pod, từ pod ra ngoài)
   # name cil_to_container    ← TC egress (packet VÀO pod, từ ngoài vào)
   # name cil_from_host       ← TC từ host network
   # name cil_to_host         ← TC lên host network

   # Xem cgroup/socket hook programs:
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | grep -B1 "cgroup_sock_addr" | grep "name"
   # name cil_sock4_connect   ← rewrite IP đích tại connect() cho service (Socket LB)
   # name cil_sock4_sendmsg   ← rewrite cho UDP sendmsg
   # name cil_sock4_recvmsg   ← reverse rewrite khi nhận response
   ```
   > **💡 Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** tính năng `sockops`/`sk_msg` (prog type `sock_ops`/`sk_msg`, tên `bpf_sockops`/`bpf_redir_proxy`) đã bị **loại bỏ hoàn toàn từ v1.14** (grep source v1.19.5 cho `sockops`/`sockmap` ra 0 kết quả). Cơ chế socket-layer hiện tại nằm trong `bpf/bpf_sock.c`, attach ở `cgroup/connect4`, `cgroup/sendmsg4`, `cgroup/recvmsg4`... (prog type `cgroup_sock_addr`), tên hàm `cil_sock4_connect`/`cil_sock4_sendmsg`/`cil_sock4_recvmsg` (và bản `_sock6_` cho IPv6). Đây là cơ chế rewrite IP:port service→backend tại `connect()` (Socket LB / kube-proxy replacement), không phải "TCP splice bypass" như sockops cũ.

3. Đếm tổng số BPF programs per type:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog list | awk '{print $2}' | sort | uniq -c | sort -rn
   # 18 sched_cls          ← 1 TC ingress + 1 TC egress per endpoint/interface
   # 12 cgroup_sock_addr   ← connect4/6, sendmsg4/6, recvmsg4/6, bind4/6, post_bind4/6...
   #  1 xdp
   ```

---

## 🔬 Thực nghiệm 2: Xem TC programs gắn trên veth của Pod

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
   # qdisc clsact ffff: dev veth3a4b5c6d parent ffff:fff1
   # ← Cilium attach clsact qdisc để có thể gắn TC programs
   ```

4. Xem TC filter (BPF programs) trên ingress và egress:
   ```bash
   # TC ingress: packet RA từ pod (từ pod ra ngoài)
   multipass exec $NODE -- tc filter show dev $VETH ingress
   # filter protocol all pref 1 bpf chain 0
   # filter protocol all pref 1 bpf ... handle 0x1 cil_from_container [...]

   # TC egress: packet VÀO pod (từ ngoài vào)
   multipass exec $NODE -- tc filter show dev $VETH egress
   # filter protocol all pref 1 bpf chain 0
   # filter protocol all pref 1 bpf ... handle 0x1 cil_to_container [...]
   ```

   *Nhận xét:* `cil_from_container` chạy khi pod gửi packet ra (egress của pod = ingress của veth nhìn từ host). Đây là nơi policy enforcement xảy ra.

---

## 🔬 Thực nghiệm 3: Verify cgroup/socket hook active (Socket LB)

**Trên `controlplane`:**

1. Verify cgroup/socket BPF program được load:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool prog show name cil_sock4_connect
   # 45: cgroup_sock_addr  name cil_sock4_connect  tag xxxx  gpl
   #     loaded_at 2024-01-01T00:00:00+0000  uid 0
   #     xlated 2KB  jited 1KB  memlock 4KB
   ```

2. Verify program attached vào cgroup (toàn bộ host):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool cgroup show /run/cilium/cgroupv2
   # ID  AttachType  AttachFlags  Name
   # 45  connect4    multi        cil_sock4_connect
   # 46  sendmsg4    multi        cil_sock4_sendmsg
   # 47  recvmsg4    multi        cil_sock4_recvmsg
   # ← Attach vào root cgroup → áp dụng cho TẤT CẢ sockets trên node
   ```

3. Xem cilium status để confirm Socket LB enabled:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium status --verbose | grep -A1 "Socket LB"
   # Socket LB:            Enabled
   # Socket LB Coverage:   Full  ← Active
   ```
   > ⚠️ **Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** field `Sockops: Enabled` chỉ có ở bản Cilium cũ (<1.11). Từ đó về sau, tính năng này gộp vào **`Socket LB`** trong mục `KubeProxyReplacement Details` — phải thêm `--verbose` mới thấy, `cilium status` (không verbose) chỉ show 1 dòng tổng `KubeProxyReplacement: True`.

---

## 💥 Thực nghiệm 4: Quan sát TC program xử lý packet thực tế

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
     cilium bpf metrics list | grep -E "Success|denied|Policy"
   # Success         EGRESS   XXX   → Tăng theo traffic được forward
   # Policy denied   INGRESS  0     → 0 nếu chưa có policy chặn
   ```
   > **💡 Lưu ý:** `REASON` chỉ có 2 nhóm giá trị thật — mã `0 = "Success"` cho packet forward thành công (không có text "Forwarded" riêng), và các mã ≥130 là lý do DROP cụ thể (`"Policy denied"`...). Không tồn tại reason `"CT: New connection"` — muốn xem connection mới dùng `cilium bpf ct list global` (Tập 24).

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
   # (timeout) ← TC cil_to_container (trên veth của hook-server) DROP trước khi vào pod
   # Lưu ý: NetworkPolicy Ingress áp cho pod ĐÍCH (hook-server) → enforce ở hook
   # "to-container" (packet VÀO pod), không phải "from-container" (packet RA pod nguồn).

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

1. **3 hook points, 3 vai trò rõ ràng:** XDP (trước SKB — DDoS/NodePort, tốc độ tối đa), TC (có SKB — policy/NAT/encap, đầy đủ tính năng), cgroup/socket hooks (socket layer — Socket LB, rewrite IP đích tại `connect()` cho service).
2. **TC dùng `clsact` qdisc:** Cilium thêm `clsact` qdisc vào mỗi veth → gắn `cil_from_container` (ingress, packet ra khỏi pod) và `cil_to_container` (egress, packet vào pod) → policy enforcement xảy ra ở đây cho cross-node traffic.
3. **cgroup/socket hook gắn vào root cgroup:** Áp dụng cho tất cả sockets trên node → intercept `connect()`/`sendmsg()`/`recvmsg()` syscall → rewrite IP:port service→backend ngay tại socket layer (Socket LB, thay kube-proxy) — same-node fast path thật sự (bỏ iptables/netfilter, vẫn qua TC BPF) nằm ở cơ chế BPF host-routing (`bpf_redirect_peer()`), xem Tập 27.
4. **Cilium auto-select:** Agent tự detect topology, tự attach đúng BPF program vào đúng hook — không cần config thủ công, không cần restart để apply thay đổi.
