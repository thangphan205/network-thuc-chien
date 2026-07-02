# Lab Tập 25: Kiến trúc Cilium — Operator, Agent, GoBGP, Hubble

Tập này khám phá từng component Cilium, so sánh với Calico, và verify Identity model (label hash → numeric ID).

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy trên cluster (từ Tập 23).
- Ít nhất 1 Pod đang chạy để xem endpoints và identities.

---

## 🔬 Thực nghiệm 1: Xem tất cả Cilium components

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

   **💡 Giải thích:** DaemonSet nghĩa là mỗi Node có đúng 1 agent, chịu trách nhiệm toàn bộ networking (routing, policy, LB, conntrack) cho Pod chạy trên chính Node đó — không có agent trung tâm nào xử lý hộ Node khác.

   **🎯 Dùng khi nào trong thực tế:** Bước health-check đầu tiên khi debug "network không hoạt động trên 1 Node cụ thể" — nếu thiếu 1 agent (Node không có dòng tương ứng, hoặc `STATUS` khác `Running`), mọi Pod trên Node đó mất networking (không route, không policy, không DNS qua Cilium). Đây gần như luôn là nghi phạm số 1 khi 1 Node "tự nhiên" bị cô lập khỏi cluster.

2. Xem Cilium Operator (1 instance per cluster):
   ```bash
   kubectl -n kube-system get pods -l name=cilium-operator
   # cilium-operator-xxxxx  1/1  Running  controlplane
   ```

   **💡 Giải thích:** Operator chỉ 1 instance active cho toàn cluster (có thể chạy nhiều replica nhưng chỉ 1 leader tại 1 thời điểm), phụ trách các việc cluster-wide: cấp phát CIDR IPAM cho từng Node, dọn `CiliumIdentity` không còn Pod nào dùng, garbage-collect CRDs — không tham gia forward packet.

   **🎯 Dùng khi nào trong thực tế:** Nếu Operator down, data-plane (agent) vẫn chạy bình thường (Pod cũ vẫn thông traffic) nhưng **Pod mới không được cấp IP** (hết CIDR đã cấp trước đó cho Node) và identity rác không được dọn (rò rỉ CRD theo thời gian). Check pod này khi gặp lỗi "pod stuck ContainerCreating vì hết IP" dù còn dư địa chỉ IP trên subnet.

3. Xem Hubble Relay (nếu enabled):
   ```bash
   kubectl -n kube-system get pods -l k8s-app=hubble-relay
   # hubble-relay-xxxxx  1/1  Running
   ```

   **💡 Giải thích:** Hubble Relay gom flow-log từ tất cả agent (mỗi agent có Hubble server local) thành 1 điểm truy vấn cluster-wide duy nhất — không có Relay thì phải query từng agent riêng lẻ qua `cilium hubble observe` trên từng Node.

   **🎯 Dùng khi nào trong thực tế:** Bắt buộc phải có nếu dùng Hubble UI/CLI để observe traffic toàn cluster (ví dụ debug "service A gọi service B bị reject ở đâu"). Thiếu Relay → chỉ xem được flow của đúng Node đang exec vào, dễ bỏ sót traffic đi qua Node khác.

4. Xem Cilium status tổng quan từ bên trong agent:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -i $CILIUM_POD -- cilium status
   # KVStore:               Ok      Disabled (Cilium dùng K8s CRDs, không cần etcd riêng)
   # Kubernetes:            Ok      1.29 (v1.29.x)
   # KubeProxyReplacement:  True    [eth0 (Direct Routing)]
   # Cilium:                Ok      1.19.5 (v1.19.5-xxxxxxx)
   # NodeMonitor:           Disabled
   # Cilium health daemon:  Ok
   # Controller Status:     24/24 healthy
   # Proxy Status:          OK, ip 10.244.1.1, 0 redirects active on ports 10000-20000
   # Hubble:                Ok      Current/Max Flows: 4096/4096
   ```
   > **💡 Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** không có field `BPF:` hay `Sockops:` đứng riêng trong `cilium status` — 2 field này không tồn tại trong formatter thật (`pkg/client/client.go`). Field `Socket LB` (thay cho `Sockops` cũ, bị loại bỏ từ v1.14) chỉ hiện khi thêm `--verbose`, nằm trong khối `KubeProxyReplacement Details:` — xem bước tiếp theo.

   **💡 Giải thích từng dòng:**
   - **`KVStore`**: Backend lưu state phối hợp giữa các agent. `Disabled` = dùng K8s CRDs thay vì etcd riêng (khác Calico truyền thống).
   - **`Kubernetes`**: Version K8s API server mà agent đang kết nối tới — mismatch version quá xa có thể gây lỗi CRD watch.
   - **`KubeProxyReplacement`**: `True` = Cilium đã thay hoàn toàn kube-proxy (eBPF service LB), kèm device dùng cho Direct Routing.
   - **`Cilium`**: Version agent đang chạy — so với version image (`cilium image (running)` từ `cilium-cli`) để phát hiện rollout dở dang (1 vài Node chưa lên version mới).
   - **`NodeMonitor`**: Cơ chế nhận event kernel qua perf ring buffer (debug packet trace) — `Disabled` là bình thường, chỉ cần bật khi debug sâu.
   - **`Proxy Status`**: Số Envoy redirect đang active — liên quan L7 policy (xem Tập 29).
   - **`Hubble: Current/Max Flows`**: Số flow đang giữ trong ring buffer / giới hạn cấu hình. Gần chạm max → flow cũ bị đẩy ra nhanh, cửa sổ quan sát lịch sử bị thu hẹp (Hubble chỉ nhớ được ít giây gần nhất).

   Muốn xem chi tiết Socket LB (service load-balancing tại `connect()`, thay cho kube-proxy), thêm `--verbose`:
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- cilium status --verbose | grep -A2 "KubeProxyReplacement Details"
   # KubeProxyReplacement Details:
   #   Status:                Strict
   #   Socket LB:             Enabled
   #   Socket LB Coverage:    Full
   ```

   **🎯 Dùng khi nào trong thực tế:** Lệnh chẩn đoán tổng quát số 1 khi nghi ngờ agent "not healthy" nhưng Pod vẫn `Running` (K8s không detect được lỗi nội bộ Cilium). Bất kỳ dòng nào khác `Ok` (ví dụ `BPF: Failure`) là dấu hiệu rõ ràng cần xem `cilium-agent` logs ngay, trước khi tốn thời gian debug ở tầng ứng dụng.

   *Nhận xét:* `KVStore: Disabled` — Calico cần etcd riêng hoặc Kubernetes API, Cilium chỉ cần K8s CRDs.

---

## 🔬 Thực nghiệm 2: Inspect Endpoints và Identities

**Trên `controlplane`:**

1. Deploy test pods với labels rõ ràng:
   ```bash
   kubectl run frontend --image=nicolaka/netshoot \
     --labels="app=frontend,env=prod" -- sleep infinity
   kubectl run backend --image=nicolaka/netshoot \
     --labels="app=backend,env=prod" -- sleep infinity
   kubectl wait --for=condition=Ready pod/frontend pod/backend --timeout=60s
   ```

   **⚠️ Quan trọng:** `cilium-agent` chỉ biết endpoint **cục bộ trên Node nó đang chạy** — `cilium endpoint list` không phải view cluster-wide dù tên gọi nghe như vậy. Scheduler có thể đặt `frontend`/`backend` lên `worker1` hay `worker2` bất kỳ, khác Node với `$CILIUM_POD` đã chọn ở Thực nghiệm 1 (`head -1` — thường rơi vào `controlplane`). Phải re-select đúng agent trên Node chứa Pod:
   ```bash
   FRONTEND_NODE=$(kubectl get pod frontend -o jsonpath='{.spec.nodeName}')
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     --field-selector spec.nodeName=$FRONTEND_NODE -o name)
   echo "Node của frontend: $FRONTEND_NODE — Cilium agent tương ứng: $CILIUM_POD"
   ```
   Nếu bỏ qua bước này, `cilium endpoint list`/`cilium bpf endpoint list` chạy nhầm agent sẽ chỉ trả về endpoint nội bộ của Node đó (`reserved:health`, `reserved:host`...) — không thấy `frontend`/`backend` đâu cả, dễ tưởng nhầm Cilium chưa attach Pod.

2. Xem endpoints Cilium đang manage:
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- \
     cilium endpoint list
   # ENDPOINT  POLICY (ingress)  POLICY (egress)  IDENTITY  IPv4
   # 1234      Disabled          Disabled          7891      10.244.1.5
   # 2345      Disabled          Disabled          12345     10.244.1.8
   # ← Mỗi Pod có IDENTITY (numeric) không phải chỉ IP
   ```

   **💡 Giải thích cột:**
   - **`ENDPOINT`**: ID nội bộ Cilium gán cho Pod trên Node này (khác `IDENTITY` — 1 endpoint = 1 Pod cụ thể, có thể đổi khi Pod restart).
   - **`POLICY (ingress/egress)`**: `Enabled` nếu Pod có ít nhất 1 `NetworkPolicy` áp dụng cho hướng đó; `Disabled` = default allow-all hướng đó (chưa có policy nào chọn Pod này).
   - **`IDENTITY`**: Số định danh bảo mật tính từ hash tập labels — dùng làm cơ sở cho identity-based policy (không phải IP-based như iptables).
   - **`IPv4`**: IP hiện tại của Pod — đổi mỗi lần Pod restart, không liên quan tới `IDENTITY`.

   **🎯 Dùng khi nào trong thực tế:** Dùng để verify Pod đã được Cilium "biết" tới chưa (Pod mới tạo mà không xuất hiện ở đây → Cilium chưa attach thành công, thường do CNI init lỗi hoặc agent chưa ready) và để tra map từ Pod → Identity khi cần đối chiếu ngược từ `cilium identity list` hoặc `cilium bpf policy list`.

3. Xem identity mapping (label → numeric ID):
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- \
     cilium identity list
   # IDENTITY  LABELS
   # 7891      k8s:app=frontend;k8s:env=prod;k8s:io.kubernetes.pod.namespace=default
   # 12345     k8s:app=backend;k8s:env=prod;k8s:io.kubernetes.pod.namespace=default
   # 1         reserved:host
   # 2         reserved:world
   ```

   **💡 Giải thích cột:**
   - **`IDENTITY`**: Numeric ID — tất cả Pod có cùng tập labels (thường là cùng Deployment/ReplicaSet) share chung 1 identity, bất kể chạy trên Node nào hay có bao nhiêu replica.
   - **`LABELS`**: Tập labels dùng để tính hash ra identity — đổi 1 label (kể cả thêm/bớt) sẽ ra identity khác hoàn toàn, không phải update tại chỗ.
   - **`reserved:host` / `reserved:world`**: Identity đặc biệt cố định (không tính từ labels) — `host` đại diện chính Node, `world` đại diện traffic từ ngoài cluster.

   **🎯 Dùng khi nào trong thực tế:** Dùng để debug policy match sai đối tượng — nếu 2 Pod đáng lẽ thuộc 2 nhóm khác nhau (ví dụ `frontend` và `backend`) lại show cùng 1 `IDENTITY`, đó là dấu hiệu 2 Deployment vô tình share label khiến `NetworkPolicy` chọn nhầm cả 2. Cũng dùng để đếm nhanh có bao nhiêu "policy class" thực sự tồn tại trong cluster (số identity ≈ số tổ hợp label distinct, không phải số Pod).

4. Xem BPF endpoint map (local endpoints — dùng cho BPF host-routing same-node):
   ```bash
   kubectl -n kube-system exec -i $CILIUM_POD -- \
     cilium bpf endpoint list
   # IP ADDRESS          LOCAL ENDPOINT INFO
   # 10.244.1.5          id=1234 ifindex=22 mac=xx:xx:xx:xx:xx:xx nodemac=yy:yy:yy:yy:yy:yy
   # ← Chỉ Pods trên node hiện tại — đây là cilium_lxc map
   ```

   **💡 Giải thích:** Đây chính là map `cilium_lxc` đã xem ở Tập 24 — phiên bản kernel-level (raw) của `cilium endpoint list`, chỉ liệt kê Pod cục bộ trên Node đang exec vào, không thấy Pod ở Node khác. Output thật chỉ có 2 cột `IP ADDRESS`/`LOCAL ENDPOINT INFO` (id/ifindex/mac gộp chung `key=value`).

   **🎯 Dùng khi nào trong thực tế:** Dùng khi nghi ngờ lệch giữa control-plane view (`cilium endpoint list`) và data-plane thật (map trong kernel) — nếu Pod xuất hiện ở `cilium endpoint list` nhưng không có trong `cilium bpf endpoint list` trên đúng Node, nghĩa là BPF program chưa sync xong xuống kernel dù agent đã "biết" Pod tồn tại (regenerate lỗi/chậm).

---

## 💥 Thực nghiệm 3: Verify Identity persist khi Pod restart

**Trên `controlplane`:**

1. Ghi lại identity của frontend pod hiện tại:
   ```bash
   OLD_IP=$(kubectl get pod frontend -o jsonpath='{.status.podIP}')
   echo "Frontend IP trước restart: $OLD_IP"

   kubectl -n kube-system exec -i $CILIUM_POD -- \
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

   # ⚠️ Pod mới có thể bị scheduler đặt sang Node khác — re-select CILIUM_POD
   FRONTEND_NODE=$(kubectl get pod frontend -o jsonpath='{.spec.nodeName}')
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     --field-selector spec.nodeName=$FRONTEND_NODE -o name)

   kubectl -n kube-system exec -i $CILIUM_POD -- \
     cilium endpoint list | grep frontend
   # ENDPOINT  ...  IDENTITY  IPv4
   # 5678      ...  7891      10.244.1.9  ← IP mới, IDENTITY vẫn 7891!
   ```

   **💡 Giải thích:** `ENDPOINT` đổi (1234 → 5678, vì đây là Pod instance mới hoàn toàn), `IPv4` đổi (IP cấp lại từ IPAM pool), nhưng `IDENTITY` giữ nguyên 7891 vì labels (`app=frontend,env=prod`) không đổi.

   **🎯 Dùng khi nào trong thực tế:** Đây là lý do Cilium xử lý rolling restart/scale nhanh hơn model IP-based (iptables/Calico thuần IP) — không cần đợi propagate policy mới cho Pod vừa lên, vì rule đã viết theo Identity chứ không theo IP. Khi debug "Pod mới restart bị mất kết nối vài giây" trong hệ IP-based, đây chính là điểm khác biệt cần biết để giải thích tại sao Cilium không gặp vấn đề tương tự (hoặc nếu vẫn gặp, vấn đề nằm ở chỗ khác, không phải policy converge).

   *Nhận xét:* Identity = hash của labels → labels không đổi → identity không đổi → policy tự apply cho Pod mới mà không cần converge.

---

## 🔬 Thực nghiệm 4: So sánh Architecture với Calico

**Trên `controlplane`:**

1. Kiểm tra Cilium Agent logs (equivalent của Felix logs):
   ```bash
   kubectl -n kube-system logs $CILIUM_POD --tail=20 | grep -i "policy\|endpoint\|identity"
   # level=info msg="Regenerating endpoints in parallel"
   # level=info msg="Successfully regenerated BPF programs"
   ```

   **💡 Giải thích:** "Regenerating endpoints" = agent đang compile lại BPF program cho 1 hoặc nhiều endpoint (do policy đổi, label đổi, hoặc Pod mới) — đây là bước sinh ra program mới rồi mới `Successfully regenerated BPF programs` (load thành công vào kernel).

   **🎯 Dùng khi nào trong thực tế:** Khi policy áp dụng nhưng chưa có hiệu lực ngay (delay vài giây là bình thường), grep log này để xem regenerate đã chạy xong chưa hay đang bị kẹt/lỗi (`level=error` thay vì `info` ở dòng regenerate — dấu hiệu compile BPF thất bại, thường do policy quá phức tạp vượt giới hạn instruction của kernel).

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

   **💡 Giải thích:** Mỗi CRD tương ứng 1 loại state Cilium cần lưu — `ciliumendpoints` gương lại `cilium endpoint list`, `ciliumidentities` gương lại `cilium identity list`, `ciliumnetworkpolicies` là CRD riêng của Cilium (mạnh hơn `NetworkPolicy` chuẩn K8s — hỗ trợ L7, FQDN, egress CIDR...).

   **🎯 Dùng khi nào trong thực tế:** Dùng để backup/restore hoặc audit state Cilium bằng công cụ K8s thuần (`kubectl get/describe/diff`) thay vì phải có quyền truy cập trực tiếp vào agent — hữu ích khi debug từ máy khác không SSH được vào Node, hoặc khi viết GitOps pipeline cần diff policy trước khi apply.

3. Xem Cilium node state (equivalent của `calicoctl node status`):
   ```bash
   kubectl get ciliumnodes
   # NAME           CILIUMINTERNALIP  INTERNALIP       AGE
   # controlplane   10.244.0.1        192.168.64.10    2d
   # worker1        10.244.1.1        192.168.64.11    2d
   # worker2        10.244.2.1        192.168.64.12    2d
   ```

   **💡 Giải thích cột:**
   - **`CILIUMINTERNALIP`**: IP overlay nội bộ Cilium gán cho Node (dùng cho traffic giữa các Node qua tunnel/native routing) — nằm trong Pod CIDR range, khác `INTERNALIP`.
   - **`INTERNALIP`**: IP thật của Node trên hạ tầng (LAN/cloud VPC) — dùng để agent giữa các Node giao tiếp với nhau (health check, BGP nếu bật GoBGP).

   **🎯 Dùng khi nào trong thực tế:** Check nhanh xem Node mới join cluster đã được Cilium cấp CIDR/IP nội bộ chưa — thiếu dòng tương ứng cho 1 Node nghĩa là `cilium-agent` trên Node đó chưa register thành công lên `CiliumNode` CRD (Pod trên Node đó sẽ không có networking dù kubelet vẫn báo Node `Ready`).

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
