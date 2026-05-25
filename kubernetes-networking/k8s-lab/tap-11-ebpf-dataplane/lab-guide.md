# Lab Tập 11: iptables vs eBPF Dataplane trong Calico

Tập này bật eBPF dataplane, quan sát BPF programs được load vào tc hooks, và so sánh với iptables mode.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 9/12.
- Ubuntu 26.04 (kernel 6.x) — đủ điều kiện eBPF.
- Không có NetworkPolicy nào đang active (dọn dẹp từ tập trước nếu cần).

---

## 🔬 Thí nghiệm 1: Kiểm tra kernel và BPF filesystem

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Kiểm tra kernel version:
   ```bash
   uname -r
   # 6.x.x-xx-generic   ← eBPF fully supported!
   ```

2. Kiểm tra BPF filesystem đã được mount:
   ```bash
   ls /sys/fs/bpf/
   # cgroup  tc  xdp    ← BPF filesystem mounted
   ```

3. Kiểm tra tc có hỗ trợ eBPF:
   ```bash
   tc qdisc show dev eth0
   # qdisc noqueue 0: root refcnt 2   ← Có thể attach eBPF program
   ```

4. Đếm iptables rules hiện tại (iptables mode):
   ```bash
   sudo iptables-save | wc -l
   # Ghi lại số này để so sánh sau
   ```

---

## 🔬 Thí nghiệm 2: Bật eBPF dataplane

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Tắt kube-proxy (eBPF Calico sẽ thay thế):
   ```bash
   kubectl patch ds kube-proxy -n kube-system \
     -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico":"true"}}}}}'
   ```

2. Verify kube-proxy không còn chạy:
   ```bash
   kubectl -n kube-system get pods | grep kube-proxy
   # (không có pods running)
   ```

3. Bật eBPF cho Calico:
   ```bash
   kubectl patch felixconfiguration default \
     --type merge \
     --patch '{"spec":{"bpfEnabled":true}}'
   ```

4. Chờ Calico reload (khoảng 30 giây):
   ```bash
   kubectl -n calico-system rollout status daemonset/calico-node
   ```

---

## 🔬 Thí nghiệm 3: Xem eBPF programs được load

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Xem tc filter programs trên eth0:
   ```bash
   tc filter show dev eth0 ingress
   # filter protocol all pref 1 bpf chain 0
   #   calico_from_host_ep.o:[calico_from_host_ep] direct-action not_in_hw...

   tc filter show dev eth0 egress
   # filter protocol all pref 1 bpf chain 0
   #   calico_to_host_ep.o:[calico_to_host_ep] direct-action not_in_hw...
   ```

2. Xem tất cả BPF programs đang chạy:
   ```bash
   sudo bpftool prog list | grep calico
   # 42: sched_cls  name calico_from_host  ...
   # 43: sched_cls  name calico_to_host    ...
   ```

3. Xem BPF maps (policy lookup tables):
   ```bash
   sudo bpftool map list | grep calico
   # 10: hash  name calico_policy_map  flags 0x0
   ```

4. Dump BPF map entries (policy rules):
   ```bash
   sudo bpftool map dump name calico_policy_map 2>/dev/null | head -20
   ```

---

## 🔬 Thí nghiệm 4: So sánh rule count

**Trên `worker1`:**

1. Đếm iptables rules sau khi bật eBPF:
   ```bash
   sudo iptables-save | wc -l
   # Ít hơn đáng kể so với trước — eBPF đã thay thế nhiều iptables rules
   ```

2. Verify veth interfaces cũng có BPF programs:
   ```bash
    # Lấy tên veth của một Pod (loại bỏ hậu tố liên kết @if để tránh lỗi tc)
    VETH=$(ip link show | grep cali | head -1 | awk '{print $2}' | cut -d'@' -f1 | tr -d ':')
    tc filter show dev $VETH ingress
   ```

3. Test kết nối Pod-to-Pod vẫn hoạt động:
   ```bash
   # Từ controlplane:
   # kubectl exec <pod> -- ping -c 3 <other-pod-ip>
   # Kết nối phải vẫn OK — eBPF xử lý thay vì iptables
   ```

4. Khôi phục iptables mode (cho các lab tiếp theo cần iptables để trace):
   ```bash
   # Từ controlplane:
   kubectl patch felixconfiguration default \
     --type merge \
     --patch '{"spec":{"bpfEnabled":false}}'

   # Restore kube-proxy
   kubectl patch ds kube-proxy -n kube-system \
     -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux"}}}}}'
   ```

---

## ✅ Tổng kết

1. **eBPF yêu cầu kernel 5.3+ nhưng Ubuntu 26.04 luôn đủ** (kernel 6.x).
2. **tc filter = attachment point:** eBPF programs gắn vào `ingress`/`egress` của từng network interface.
3. **bpftool:** Công cụ debug xem programs đang load và map entries (policy rules).
4. **eBPF thay kube-proxy:** Calico eBPF mode không cần kube-proxy — service routing được xử lý trong BPF maps.
5. **Lab tiếp theo dùng iptables mode** để dễ trace bằng `iptables -L` và LOG rules.
