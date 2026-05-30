# Lab Tập 11: iptables vs eBPF Dataplane trong Calico

Tập này bật eBPF dataplane, quan sát BPF programs được load vào tc hooks, và so sánh với iptables mode.

## Tại sao eBPF?

| | iptables | eBPF |
|---|---|---|
| Policy lookup | O(n) — duyệt tuần tự từng rule | O(1) — hash map lookup |
| Service routing | kube-proxy + iptables DNAT | BPF maps, bypass netfilter |
| Latency | +overhead mỗi rule thêm | flat, không phụ thuộc số rules |
| DSR | Không hỗ trợ | Direct Server Return — client thấy server IP thật |

---

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 9 (Calico **3.20+** — eBPF stable từ version này).
- Ubuntu 26.04 (kernel 6.x) — đủ điều kiện eBPF.
- Không có NetworkPolicy nào đang active (dọn dẹp từ tập trước nếu cần).
- `bpftool` đã cài trên **tất cả worker nodes**:
  ```bash
  sudo apt install -y linux-tools-common linux-tools-$(uname -r)
  # Nếu package không tìm thấy:
  sudo apt install -y bpftool
  ```

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

3. Kiểm tra bpftool có sẵn (sẽ dùng ở thí nghiệm sau):
   ```bash
   sudo bpftool version
   # libbpf v1.x.x
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

5. **Verify eBPF thực sự đã bật:**
   ```bash
   # Confirm config
   kubectl get felixconfiguration default -o jsonpath='{.spec.bpfEnabled}'
   # true

   # Confirm calico-node logs nhận eBPF mode
   kubectl logs -n calico-system daemonset/calico-node -c calico-node \
     | grep -i "BPF\|eBPF" | tail -10
   # ... "BPF enabled" hoặc "Starting BPF endpoint manager"
   ```

---

## 🔬 Thí nghiệm 3: Xem eBPF programs được load

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Xem các eBPF programs được load trên network interfaces:
   * **Cách 1: Sử dụng bpftool net (KHUYÊN DÙNG cho Kernel 6.x trở lên):**
     Vì Ubuntu 26.04 chạy Kernel 6.x mới, Calico tự động sử dụng cơ chế nạp eBPF hiện đại tên là **`tcx`** (thông qua BPF links) thay thế cho cơ chế `tc filter` cổ điển. Vì gắn qua `tcx`, lệnh `tc filter show` cũ sẽ trả về kết quả trống trơn.
     Hãy chạy lệnh sau để quét toàn bộ:
     ```bash
     sudo bpftool net show
     # Bạn sẽ thấy các card mạng enp0s1, vxlan.calico, cali...
     # đều đã được gắn chương trình `cali_tc_preamble` qua tcx/ingress và tcx/egress!
     ```
   * **Cách 2: Sử dụng `tc filter` cổ điển (Chỉ hoạt động trên Kernel cũ < 6.2):**
     ```bash
     tc filter show dev enp0s1 ingress
     ```


2. Xem tất cả BPF programs đang chạy:
   ```bash
   sudo bpftool prog list | grep calico
   # 42: sched_cls  name calico_from_host  tag ...
   # 43: sched_cls  name calico_to_host    tag ...
   ```

3. Xem BPF maps (policy lookup tables):
   ```bash
   sudo bpftool map list | grep cali
   # 10: hash  name cali_v4_pol_pf   flags 0x0
   # 11: hash  name cali_v4_nat_fe   flags 0x0
   # ...
   ```

4. Dump BPF map entries (policy rules):
   ```bash
   # Lấy ID của một map từ bước trên, ví dụ ID=10
   MAP_ID=$(sudo bpftool map list | grep cali_v4_pol | head -1 | awk '{print $1}' | tr -d ':')
   sudo bpftool map dump id $MAP_ID | head -20
   # Nếu không có map nào tên cali_v4_pol, thử:
   sudo bpftool map list | grep cali
   # Chọn ID phù hợp và dump
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
5. **DSR (Direct Server Return):** Client thấy server IP thật thay vì node IP — chỉ có trong eBPF mode.
6. **Lab tiếp theo dùng iptables mode** để dễ trace bằng `iptables -L` và LOG rules.
