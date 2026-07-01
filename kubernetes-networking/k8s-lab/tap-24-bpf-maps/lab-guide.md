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
   kubectl -n kube-system exec -i $CILIUM_POD -- \
     bpftool map list | head -40
    # Output dạng:
    # 12: hash  name cilium_policy_00023  flags 0x0
    #     key 24B  value 8B  max_entries 16384
    # 63: lru_hash  name cilium_ct4_glob  flags 0x0
    #     key 24B  value 56B  max_entries 524288
    # ...
    ```

    > **💡 Lưu ý về tên Map conntrack:** Do giới hạn **15 ký tự** của Linux Kernel đối với tên đối tượng BPF, tên gốc `cilium_ct4_global` bị Kernel cắt ngắn bớt thành `cilium_ct4_glob`! Ở các bản Cilium cũ hơn, bạn có thể thấy tên `cilium_ct_tcp4`.

   **💡 Giải thích các thông số trong output:**
   - **`12:` / `13:`**: Map ID - Định danh duy nhất của Map trong kernel.
   - **`hash` / `lru_hash` / `array`**: Kiểu dữ liệu cấu trúc của Map.
   - **`name cilium_policy_...`**: Tên của Map, giúp lập trình viên và CLI dễ nhận diện.
   - **`key 24B`**: Độ rộng của Key là 24 Bytes (chứa thông tin IP, port...).
   - **`value 8B`**: Độ rộng của Value là 8 Bytes (chứa action ALLOW/DROP...).
   - **`max_entries`**: Giới hạn số lượng bản ghi tối đa trong Map. Ví dụ `cilium_ct4_glob` (hoặc `cilium_ct_tcp4`) có thể chứa tới 524.288 kết nối đồng thời.

3. Đếm số maps Cilium đang dùng:
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- \
     bpftool map list | grep -c "^[0-9]"
   # Thường 30-60 maps tùy số endpoints
   ```

4. Phân loại theo type:
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- \
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
    # Dùng python3 HTTP server thay vì nc để curl không bị báo lỗi "Empty reply"
    kubectl run ct-server --image=nicolaka/netshoot -- python3 -m http.server 8080
    kubectl wait --for=condition=Ready pod/ct-client pod/ct-server --timeout=60s
    SERVER_IP=$(kubectl get pod ct-server -o jsonpath='{.status.podIP}')
   ```

2. Tạo vài connections:
    ```bash
    for i in $(seq 1 5); do
      kubectl exec ct-client -- curl -s -o /dev/null http://$SERVER_IP:8080
    done
    ```

3. Xác định Node và lấy đúng Cilium Pod tương ứng:
   > **⚠️ Lưu ý cực kỳ quan trọng:** BPF Maps được lưu cục bộ (node-local) trong bộ nhớ của từng Node. Do đó, kết nối giữa `ct-client` và `ct-server` chỉ xuất hiện trên bảng Conntrack của Node mà chúng đang chạy (ở đây là Node của `ct-server`). Nếu bạn dùng Cilium Agent pod ở Node khác (như controlplane), bảng conntrack sẽ không có thông tin của 2 Pod này!

   ```bash
   # Lấy tên Node của ct-server
   NODE_NAME=$(kubectl get pod ct-server -o jsonpath='{.spec.nodeName}')
   echo "ct-server đang chạy ở node: $NODE_NAME"

   # Lấy Cilium Agent pod tương ứng với Node đó
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     --field-selector spec.nodeName=$NODE_NAME -o name)
   echo "Cilium pod trên node $NODE_NAME: $CILIUM_POD"
   ```

4. Xem conntrack table trên đúng node đó:
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- \
     cilium bpf ct list global | head -20
   # TCP IN  10.244.2.9:45123 -> 10.244.2.3:8080
   #   expires=3720 RxPackets=42 RxBytes=8764
   #   TxPackets=38 TxBytes=7412 Flags=0x0
   ```

   **💡 Giải thích dòng output:**
   - **`TCP IN`**: Gói tin thuộc giao thức TCP đi vào (ingress).
   - **`10.244.2.9:45123 -> 10.244.2.3:8080`**: Kết nối từ client nguồn (`ct-client` IP: 10.244.2.9) tới server đích (`ct-server` IP: 10.244.2.3).
   - **`expires=3720`**: Số giây còn lại trước khi connection entry này hết hạn và bị xóa khỏi bộ nhớ (nếu không có packet mới phát sinh).
   - **`RxPackets/RxBytes` và `TxPackets/TxBytes`**: Thống kê số lượng gói tin/dung lượng byte đã trao đổi qua lại cho kết nối này.

5. Đếm active connections:
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- \
     cilium bpf ct list global | wc -l
   # Số entries trong LRU hash map
   ```

   **💡 Nhận xét cốt lõi về LRU:**
   Trong hệ thống mạng truyền thống, nếu bị tấn công DDoS (tạo ra hàng triệu connection rác trong thời gian ngắn), bảng conntrack mặc định (`nf_conntrack`) sẽ bị tràn dẫn tới treo máy hoặc rớt gói tin. 
   Với Cilium dùng **LRU (Least Recently Used) Hash Map**:
   - Khi bảng đạt giới hạn (ví dụ 512K entries), các kết nối cũ nhất không có traffic sẽ tự động bị đẩy ra (evict) để nhường chỗ cho kết nối mới.
   - Hoạt động lockless (per-CPU) giúp việc cập nhật bảng conntrack không bị nghẽn khóa (lock contention) trên các máy chủ nhiều CPU cores.

6. Xem dữ liệu thô (raw hex) của bảng conntrack trong Kernel:
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- bash -c '
     bpftool map dump name cilium_ct4_glob 2>/dev/null || bpftool map dump name cilium_ct_tcp4
   ' | head -10
   # Output dạng:
   # key:
   # 0a f4 00 02 00 00 b0 1b 0a f4 00 03 00 00 1f 90 06 00 00 00 00 00 00 00
   # value:
   # 03 00 00 00 00 00 00 00 8c 8f 20 68 00 00 00 00 2a 00 00 00 00 00 00 00
   ```

   > **💡 Vì sao dùng `map dump name` thay vì `map dump id`?** `bpftool` cho phép chọn map trực tiếp bằng tên (`name <MAP_NAME>`) thay vì phải chạy `map list`, `grep` tên map rồi `cut` lấy ID ra trước — đỡ 1 bước trung gian, cũng tránh lỗi khi grep không match (ID rỗng → lệnh dump báo lỗi mơ hồ). Vì tên map thay đổi giữa các bản Cilium (`cilium_ct4_glob` cũ hơn là `cilium_ct_tcp4`), lệnh thử tên mới trước, lỗi thì fallback tên cũ.

   **💡 Giải thích:** Lệnh `bpftool map dump` hiển thị trực tiếp dữ liệu nhị phân dưới dạng hex được lưu trữ trong bộ nhớ Kernel — mỗi record gồm 1 dòng `key:` (struct tuple 4: src_ip, src_port, dst_ip, dst_port, proto...) và 1 dòng `value:` (state, timestamp, counters...). BPF program sử dụng cấu trúc này để tra cứu kết nối siêu tốc $O(1)$ trong thời gian thực.

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

   **💡 Giải thích các cột trong Policy Map:**
   - **`ENDPOINT`**: ID của container/pod nội bộ nằm trên node này.
   - **`DIRECTION`**: Hướng traffic (`ingress`: đi vào pod, `egress`: đi ra khỏi pod).
   - **`IDENTITY`**: Nhãn định danh bảo mật của Cilium (Cilium gom các Pod cùng labels thành một số Identity duy nhất thay vì dùng IP để tối ưu hóa lookup).
   - **`ACTION`**: Hành vi thực thi (`ALLOW` hoặc `DROP`).

2. Xem metrics map (Per-CPU Hash Map):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf metrics list
   # REASON                DIRECTION   PACKETS   BYTES
   # Forwarded             egress      8891      2.1MB
   # Policy denied         ingress     0         0
   # CT: New connection    ingress     142       89320
   ```

   **💡 Giải thích về Metrics Map:**
   - Map này lưu trữ thống kê số lượng packet/bytes tương ứng với từng sự kiện (Ví dụ: số packet được forward, số packet bị drop do policy).
   - Do đây là **Per-CPU Hash Map**, mỗi CPU core tự ghi đếm độc lập mà không cần lock chung. Lệnh hiển thị trên đã tự động cộng gộp (sum) dữ liệu từ tất cả các CPU cores của node để trả về con số tổng thể.

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

   # Tạo lưu lượng bị cấm (sẽ bị block)
   kubectl exec ct-client -- curl -s --max-time 2 http://$SERVER_IP:8080 || true

   # Kiểm tra số lượng packet bị từ chối tăng lên
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf metrics list | grep "denied\|Policy"
   # Policy denied  ingress  5  3840  ← Tăng!
   ```

   **💡 Cơ chế hoạt động:**
   Khi áp dụng `NetworkPolicy`, Cilium Agent tính toán lại luật và ghi đè trực tiếp vào Map `cilium_policy_<endpoint_id>` trong Kernel. Khi `ct-client` gửi packet đến `ct-server`, eBPF program chạy ở tầng network nhận dạng packet -> đối chiếu Map thấy không được phép -> DROP gói tin ngay lập tức và tăng biến đếm drop trong Per-CPU metrics map. Tất cả diễn ra hoàn toàn trong kernel space mà không cần gọi tiến trình xử lý ở User Space.

4. Xem endpoint map cục bộ trên node (cilium_lxc map):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf endpoint list
   # ENDPOINT  FLAGS  IPv4        MAC
   # 1234      0x0    10.244.2.9  xx:xx:xx:xx:xx:xx
   # 2345      0x0    10.244.2.3  yy:yy:yy:yy:yy:yy
   ```

   **💡 Ý nghĩa của Local Endpoint Map (cilium_lxc):**
   - Bản đồ này chỉ lưu danh sách các Pods chạy cục bộ trên chính Node đó.
   - Khi tính năng `sockops` (Socket Operations) hoạt động, nó sẽ tra cứu map này. Nếu phát hiện IP của Pod nguồn và Pod đích đều nằm trên cùng một Node, nó sẽ "nối tắt" trực tiếp hai socket TCP của hai container lại với nhau trong Kernel (bypass qua toàn bộ TCP/IP network stack của OS để tăng hiệu năng).

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
