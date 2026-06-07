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
- Ubuntu 26.04 (kernel 6.x/7.x+) — đủ điều kiện eBPF.
- Không có NetworkPolicy nào đang active (dọn dẹp từ tập trước nếu cần).
- `bpftool` đã cài trên **tất cả worker nodes**:
  ```bash
  sudo apt update && sudo apt install -y bpftool
  ```

---

## 🔬 Thực nghiệm 1: Kiểm tra kernel và BPF filesystem

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

3. Kiểm tra bpftool có sẵn (sẽ dùng ở thực nghiệm sau):
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

## 🔬 Thực nghiệm 2: Bật eBPF dataplane

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

## 🔬 Thực nghiệm 3: Xem eBPF programs được load

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
     > 💡 **Giải thích chi tiết Output `bpftool net show`:**
     > * `enp0s1(2)` / `vxlan.calico(13)` / `cali...`: Tên card mạng vật lý hoặc ảo và ID trong OS.
     > * `tcx/ingress` / `tcx/egress`: Điểm gắn BPF hook theo cơ chế tcx hiện đại (ingress: chiều đi vào card, egress: chiều đi ra).
     > * `cali_tc_preamble`: Tên chương trình BPF mồi của Calico chạy trước để giải phóng/phân tích sơ bộ gói tin.
     > * `prog_id`: ID định danh duy nhất của chương trình eBPF trong bộ nhớ Kernel.
     > * `link_id`: ID biểu diễn BPF Link liên kết chặt chẽ chương trình BPF với card mạng đó.

   * **Cách 2: Sử dụng `tc filter` cổ điển (Chỉ hoạt động trên Kernel cũ < 6.6):**
     ```bash
     tc filter show dev enp0s1 ingress
     ```


2. Xem tất cả BPF programs đang chạy:
   ```bash
   sudo bpftool prog list | grep cali
   # 42: sched_cls  name cali_tc_ingress  tag ...
   ```
   > 💡 **Giải thích chi tiết Output `bpftool prog list`:**
   > * `sched_cls`: Loại chương trình eBPF (Classifier dùng cho bộ điều phối Traffic Control của Linux).
   > * `tag <hash>`: Mã băm đại diện cho tập chỉ thị lệnh (instructions) của chương trình này.
   > * `xlated / jited`: Kích thước bytecode ảo và kích thước mã máy thật được JIT (Just-In-Time) biên dịch để CPU thực thi trực tiếp ở tầng phần cứng với tốc độ ánh sáng.
   > * `map_ids`: ID của các bảng BPF Maps mà chương trình này được phép đọc/ghi dữ liệu để tra cứu trạng thái mạng.

3. Xem BPF maps (policy lookup tables):
   ```bash
   sudo bpftool map list | grep cali
   # 10: hash  name cali_v4_pol_pf   flags 0x0
   # 11: hash  name cali_v4_nat_fe   flags 0x0
   # ...
   ```
   > 💡 **Giải thích chi tiết Output `bpftool map list`:**
   > * `hash`: Kiểu cấu trúc dữ liệu bảng băm, giúp tìm kiếm với độ phức tạp phẳng $O(1)$ bất kể số lượng Pod.
   > * `cali_v4_pol_pf`: Map chứa các chính sách bảo mật NetworkPolicy IPv4 dành cho Pods.
   > * `cali_v4_nat_fe`: Map lưu trữ cấu hình NAT Frontend (thay thế cho kube-proxy để cân bằng tải Service).
   > * `key 8B / value 4B`: Kích thước Khóa tìm kiếm (8 Bytes) và Giá trị hành động trả về (4 Bytes).
   > * `max_entries 1048576`: Dung lượng tối đa của bảng băm (lên đến hơn 1 triệu dòng băm), cho thấy khả năng scale khổng lồ của eBPF.

4. Dump BPF map entries (Ví dụ: Xem bảng định tuyến hoặc bảng chính sách):
   ```bash
   # Lấy ID của map định tuyến cali_v4_routes (Map này luôn luôn có sẵn mặc định)
   MAP_ID=$(sudo bpftool map list | grep cali_v4_routes | head -1 | awk '{print $1}' | tr -d ':')
   
   # Dump bảng định tuyến eBPF để xem dải IP Pod và IP các Node
   sudo bpftool map dump id $MAP_ID | head -25

   # Lưu ý: Bảng map lưu chính sách (cali_v4_pol) chỉ được khởi tạo khi có ít nhất 1 NetworkPolicy đang active trong cụm.
   # Nếu có policy hoạt động, bạn có thể dump bảng chính sách bằng lệnh:
   # POLICY_MAP_ID=$(sudo bpftool map list | grep cali_v4_pol | head -1 | awk '{print $1}' | tr -d ':')
   # sudo bpftool map dump id $POLICY_MAP_ID | head -20
   ```
   > 💡 **Giải thích chi tiết Map Dump (JSON cấu trúc trên Kernel mới hoặc Hex trên Kernel cũ):**
   > * **Nếu hiển thị dạng JSON (Nhờ BTF metadata trên Ubuntu mới):**
   >   * `"protocol": 1`: Đại diện cho giao thức **ICMP** (Ping). Nếu là `17` thì là **UDP**, `6` là **TCP**.
   >   * `"addr_a": 1136522250`: Địa chỉ IP nguồn dạng số nguyên (Little-endian). Đổi `1136522250` sang Hex là `0x43be140a` -> đọc ngược từ phải sang trái: `0a.14.be.43` -> IP Pod: **`10.20.190.67`**!
   >   * `"addr_b": 2213278730`: Địa chỉ IP đích dạng số nguyên. Đổi `2213278730` sang Hex là `0x83eefc0a` -> đọc ngược: `0a.fc.ee.83` -> IP Pod: **`10.252.238.131`**!
   >   * `"packets": 208`: Thống kê số lượng gói tin đi qua luồng này do eBPF tự động ghi nhận theo thời gian thực!
   > * **Nếu hiển thị dạng Hex thô (Trên các Kernel cũ không có BTF):**
   >   * `key`: Ví dụ `0a f4 01 05 00 00 00 00` -> Dịch từ Hex sang hệ 10: `0a`=10, `f4`=244, `01`=1, `05`=5 -> Đại diện cho địa chỉ IP Pod: **`10.244.1.5`**.
   >   * `value`: Ví dụ `01 00 00 00` -> Cờ nhị phân đại diện cho hành động **`ALLOW`** (Cho phép đi qua). Nếu là `00 00 00 00` hoặc mã khác sẽ tương đương hành động **`DROP`** (Chặn gói tin).



---

## 🔬 Thực nghiệm 4: So sánh rule count

**Trên `worker1`:**

1. Đếm iptables rules sau khi bật eBPF:
   ```bash
   sudo iptables-save | wc -l
   # Ít hơn đáng kể so với trước — eBPF đã thay thế nhiều iptables rules
   ```

2. Verify veth interfaces cũng có BPF programs:
   * **Cách 1: Xem qua bpftool net (KHUYÊN DÙNG cho Kernel 6.x/7.x):**
     Các interface ảo `cali...` nối từ Host vào Pod cũng sử dụng cơ chế nạp `tcx` hiện đại. Hãy chạy lệnh:
     ```bash
     sudo bpftool net show | grep cali
     # Bạn sẽ thấy các card cali... được gắn tcx/ingress và egress thành công!
     ```
   * **Cách 2: Sử dụng `tc filter` cổ điển (Chỉ chạy trên Kernel cũ < 6.6):**
     ```bash
     # Lấy tên veth của một Pod (loại bỏ hậu tố liên kết @if để tránh lỗi tc)
     VETH=$(ip link show | grep cali | head -1 | awk '{print $2}' | cut -d'@' -f1 | tr -d ':')
     tc filter show dev $VETH ingress
     ```

3. Test kết nối Pod-to-Pod vẫn hoạt động:
   ```bash
   # Lấy IP của pod-b (trên worker2) từ controlplane:
   POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
   
   # Ping thử từ pod-a (trên worker1):
   kubectl exec pod-a -- ping -c 3 $POD_B_IP
   # Kết quả: Kết nối thành công bình thường — eBPF định tuyến siêu tốc thay vì iptables!
   ```
   * **Xác minh eBPF thực sự đang xử lý traffic (Qua eBPF Conntrack Map):**
     Khi gói tin ping đi qua, bộ theo dõi kết nối (Conntrack) của eBPF sẽ ghi nhận dòng traffic này vào map `cali_v4_ct`. 
     Hãy chạy lệnh sau trên **`worker1`** để kiểm chứng dòng traffic đang được eBPF theo dõi trực tiếp trong Kernel:
     ```bash
     # Lấy ID của map conntrack cali_v4_ct
     CT_MAP_ID=$(sudo bpftool map list | grep -E "cali_v4_ct|conntrack" | head -1 | awk '{print $1}' | tr -d ':')
     
     # Dump bảng conntrack và lọc dải IP 10.244.x.x (Hex là 0a f4)
     sudo bpftool map dump id $CT_MAP_ID | grep -E "0a f4"
     # Kết quả: Thấy các dòng bản ghi Hex chứa địa chỉ IP Pod của bạn đang được eBPF giám sát trực tiếp!
     ```

4. Thử nghiệm chặn lọc bằng eBPF (Áp dụng Deny-All & Xem BPF Map thay đổi):

   **Trên `controlplane`:**
   * Tạo chính sách chặn toàn bộ Ingress (Deny-All) vào cụm:
     ```bash
     kubectl apply -f - <<'EOF'
     apiVersion: networking.k8s.io/v1
     kind: NetworkPolicy
     metadata:
       name: deny-all-test
     spec:
       podSelector: {}
       policyTypes:
       - Ingress
     EOF
     ```
   * Ping lại để kiểm tra:
     ```bash
     kubectl exec pod-a -- ping -c 3 $POD_B_IP -W 2
     # Kết quả: Bị CHẶN đứng hoàn toàn (Packet Loss 100%)!
     ```

   **Quay lại `worker1` để kiểm tra BPF Maps:**
   * **Một sự thật kiến trúc thú vị:** Nếu chạy lệnh `sudo bpftool map list | grep cali_v4`, bạn sẽ **không thấy** bất kỳ bảng map nào tên là `cali_v4_pol`.
     *Lý do:* Trong thiết kế của Calico eBPF, **NetworkPolicies không được lưu trong BPF Maps** (khác biệt lớn so với Cilium). Thay vào đó, Felix sẽ **biên dịch trực tiếp (JIT-compile) các luật chính sách mạng thành tập lệnh mã máy eBPF (bytecode)** và nạp đè nguyên khối (atomic swap) vào card mạng ảo `cali...` của Pod. 
     Do đó, luật chặn `deny-all` đã biến thành các dòng code lệnh rẽ nhánh chạy trực tiếp trong nhân Kernel thay vì lưu trong bảng tra cứu!

   * **Cách kiểm chứng eBPF đang thực thi chặn:**
     Mặc dù không có Map chính sách, chúng ta có thể kiểm tra bảng theo dõi kết nối **`cali_v4_ct4`** (Bảng Conntrack của Calico eBPF trên máy bạn chính là `cali_v4_ct4`) để xem luồng traffic ping vừa rồi đã bị ngắt hoặc không được duyệt (`approved` chuyển về false):
     ```bash
     # Lấy ID của map conntrack cali_v4_ct4
     CT_MAP_ID=$(sudo bpftool map list | grep cali_v4_ct4 | head -1 | awk '{print $1}' | tr -d ':')
     
     # Dump bảng conntrack để xem trạng thái kết nối
     sudo bpftool map dump id $CT_MAP_ID | head -30
     ```
     > 💡 **Giải thích chi tiết Kết quả Conntrack Map Dump (Dạng JSON nhờ BTF):**
     > * **Khóa tìm kiếm luồng (`"key"`):**
     >   * `"protocol": 17`: Giao thức **UDP** (hoặc `1` là **ICMP Ping**).
     >   * `"port_b": 123`: Cổng đích `123` của dịch vụ **NTP** đồng bộ giờ hệ thống.
     >   * `"addr_a": 1039968448`: Địa chỉ IP nguồn dạng số nguyên (Little-Endian). Đổi `1039968448` sang Hex là `0x3dfca8c0` -> đọc ngược byte mạng: `c0.a8.fc.3d` -> dịch sang hệ 10 chính là **`192.168.252.61`** (IP vật lý của máy `worker1`!).
     > * **Hành động của eBPF (`"value"`):**
     >   * `"a_to_b" → "approved": 0x0`: Dòng traffic từ Host gửi yêu cầu ra ngoài **không được eBPF phê duyệt** (`approved` bằng 0). Đây là bằng chứng thép eBPF đang chặn đứng hoàn toàn kết nối này ngay tại tầng Kernel!



   **Dọn dẹp chính sách test trên `controlplane`:**
   * Xóa chính sách deny-all để trả lại trạng thái kết nối sạch:
     ```bash
     kubectl delete netpol deny-all-test
     ```

5. Khôi phục iptables mode (cho các lab tiếp theo cần iptables để trace):

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

1. **eBPF yêu cầu kernel 5.3+ nhưng Ubuntu 26.04 luôn đủ** (kernel 6.x/7.x+).
2. **tc filter = attachment point:** eBPF programs gắn vào `ingress`/`egress` của từng network interface.
3. **bpftool:** Công cụ debug xem programs đang load và map entries (policy rules).
4. **eBPF thay kube-proxy:** Calico eBPF mode không cần kube-proxy — service routing được xử lý trong BPF maps.
5. **DSR (Direct Server Return):** Client thấy server IP thật thay vì node IP — chỉ có trong eBPF mode.
6. **Lab tiếp theo dùng iptables mode** để dễ trace bằng `iptables -L` và LOG rules.
