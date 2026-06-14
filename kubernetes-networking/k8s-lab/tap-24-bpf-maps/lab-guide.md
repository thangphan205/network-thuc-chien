# Lab Tập 24: BPF Maps — Inspect Hash, LRU, Array, Per-CPU trong Cilium

Tập này inspect BPF Maps trực tiếp qua `bpftool` và Cilium CLI để hiểu cách Cilium lưu policy, conntrack state, và metrics ở kernel level.

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy trên cluster (từ Tập 23).
- `bpftool` có sẵn trong cilium-agent container.

---

## 🔬 Thực nghiệm 1: List tất cả BPF Maps Cilium tạo

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Lấy tên cilium-agent pod:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)
   echo "Cilium pod: $CILIUM_POD"
   ```

2. List tất cả BPF maps:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool map list | head -40
   # Output dạng:
   # 12: hash  name cilium_policy_00023  flags 0x0
   #     key 24B  value 8B  max_entries 16384
   # 13: lru_hash  name cilium_ct_tcp4  flags 0x0
   #     key 24B  value 56B  max_entries 524288
   # 14: array  name cilium_calls_00023  flags 0x0
   # ...
   ```

3. Đếm số maps Cilium đang dùng:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool map list | grep -c "^[0-9]"
   # Thường 30-60 maps tùy số endpoints
   ```

4. Phân loại theo type:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     bpftool map list | grep -E "^[0-9]+:" | awk '{print $2}' | sort | uniq -c | sort -rn
   # hash          15  ← Policy maps
   # lru_hash       4  ← Conntrack maps
   # array         20  ← Config/calls maps
   # percpu_hash    3  ← Metrics maps
   ```

---

## 🔬 Thực nghiệm 2: Xem Conntrack Table (LRU Hash Map)

**Trên `controlplane`:**

1. Deploy test pods để tạo traffic:
   ```bash
   kubectl run ct-client --image=nicolaka/netshoot -- sleep infinity
   kubectl run ct-server --image=nicolaka/netshoot -- nc -lk -p 8080
   kubectl wait --for=condition=Ready pod/ct-client pod/ct-server --timeout=60s
   SERVER_IP=$(kubectl get pod ct-server -o jsonpath='{.status.podIP}')
   ```

2. Tạo vài connections:
   ```bash
   for i in $(seq 1 5); do
     kubectl exec ct-client -- curl -s -o /dev/null http://$SERVER_IP:8080 || true
   done
   ```

3. Xem conntrack table:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf ct list global | head -20
   # TCP IN  10.244.1.5:8080 -> 10.244.2.8:45123
   #   expires=3720 RxPackets=42 RxBytes=8764
   #   TxPackets=38 TxBytes=7412 Flags=0x0
   ```

4. Đếm active connections:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf ct list global | wc -l
   # Số entries trong LRU hash map
   ```

   *Nhận xét:* Conntrack LRU không cần lock → scale tốt với nhiều CPU. Khi full (512K entries default), oldest entry tự bị evict.

---

## 🔬 Thực nghiệm 3: Xem Policy Map và Metrics

**Trên `controlplane`:**

1. Xem policy map (Hash Map):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf policy list
   # ENDPOINT  DIRECTION  IDENTITY  PORT/PROTO  ACTION
   # 1234      ingress    0         ANY         ALLOW  (world)
   # 1234      egress     0         ANY         ALLOW
   ```

2. Xem metrics map (Per-CPU Hash Map):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf metrics list
   # REASON                DIRECTION   PACKETS   BYTES
   # Forwarded             egress      8891      2.1MB
   # Policy denied         ingress     0         0
   # CT: New connection    ingress     142       89320
   ```

3. Deploy một NetworkPolicy để thấy denied metrics tăng:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: deny-ct-client
   spec:
     podSelector:
       matchLabels:
         run: ct-server
     policyTypes:
     - Ingress
     ingress: []
   EOF

   # Generate denied traffic
   kubectl exec ct-client -- curl -s --max-time 2 http://$SERVER_IP:8080 || true

   # Xem metrics tăng
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf metrics list | grep "denied\|Policy"
   # Policy denied  ingress  5  3840  ← Tăng!
   ```

---

## 💥 Thực nghiệm 4: Demo O(1) BPF vs O(n) iptables

**Trên `controlplane`:**

1. Đo thời gian lookup iptables với nhiều rules (trên worker1):
   ```bash
   multipass exec worker1 -- bash -c "
     # Thêm 500 rules tạm
     for i in \$(seq 1 500); do
       sudo iptables -A OUTPUT -d 203.0.113.\$((i % 254 + 1)) -j ACCEPT 2>/dev/null || true
     done
     echo 'Rules added'
     # Đo thời gian list rules
     time sudo iptables -L OUTPUT --line-numbers > /dev/null
     # Cleanup
     sudo iptables -F OUTPUT
   "
   # real: 0m2-4s (linear với số rules)
   ```

2. So sánh: BPF map lookup không thay đổi dù có nhiều entries:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- bash -c "
     # BPF map lookup O(1) — thời gian không đổi dù có 100K entries
     MAP_ID=\$(bpftool map list | grep 'cilium_ct_tcp4' | awk '{print \$1}' | tr -d ':' | head -1)
     echo 'Map ID: '\$MAP_ID
     # Đây là illustration — actual lookup trong BPF program xảy ra trong nanoseconds
     bpftool map show id \$MAP_ID
   "
   # max_entries: 524288 — dù có 500K entries, lookup vẫn O(1)
   ```

3. Verify cilium_lxc map (local endpoint map — quan trọng cho sockops):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf endpoint list
   # ENDPOINT  FLAGS  IPv4        MAC
   # 1234      0x0    10.244.1.5  xx:xx:xx:xx:xx:xx
   # 2345      0x0    10.244.1.8  yy:yy:yy:yy:yy:yy
   # ← Chỉ Pods trên NODE NÀY → sockops lookup map này
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod ct-client ct-server
kubectl delete networkpolicy deny-ct-client
```

---

## ✅ Tổng kết

1. **BPF Maps = shared memory kernel↔userspace:** cilium-agent ghi policy vào BPF Map, BPF program trong kernel đọc per-packet — không có syscall overhead, không context switch.
2. **4 loại Map cho 4 use case:** Hash (policy O(1)), LRU Hash (conntrack lockless), Array (config/calls), Per-CPU Hash (metrics no-lock counters).
3. **LRU Hash thay nf_conntrack:** Auto-evict oldest entry khi full → không crash, không block — quan trọng khi có DDoS tạo nhiều connections.
4. **`cilium bpf endpoint list` = cilium_lxc map:** Chứa chỉ Pods trên node hiện tại → đây là cơ chế sockops detect "same-node" để redirect socket trực tiếp.
