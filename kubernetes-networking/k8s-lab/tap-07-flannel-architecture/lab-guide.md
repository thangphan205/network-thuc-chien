# Lab Tập 7: Kiến trúc Flannel — flanneld, subnet.env, FDB và ARP

Trong Tập 6, bạn thấy Flannel "hoạt động". Tập này đi sâu vào bên trong: flanneld lấy dữ liệu từ đâu? CNI plugin biết gán IP range nào? VTEP định vị Node đích bằng cơ chế gì?

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s 3 node với Flannel VXLAN đang chạy (kết quả từ Tập 6).
- `pod-a` chạy trên `worker1`, `pod-b` chạy trên `worker2` (từ Tập 6).

---

## 🔬 Thí nghiệm 1: Đọc subnet allocation từ K8s API

flanneld không dùng etcd riêng — nó đọc trực tiếp từ K8s API.

**SSH vào `controlplane`:**

1. Xem `podCIDR` được cấp cho từng Node — đây là dữ liệu flanneld đọc để biết subnet nào thuộc về Node nào:
   ```bash
   multipass shell controlplane
   kubectl get nodes -o custom-columns='NAME:.metadata.name,PODCIDR:.spec.podCIDR,IP:.status.addresses[0].address'
   ```
   *Kết quả mong đợi:*
   ```
   NAME           PODCIDR          IP
   controlplane   10.244.0.0/24    192.168.64.10
   worker1        10.244.1.0/24    192.168.64.11
   worker2        10.244.2.0/24    192.168.64.12
   ```
   *Nhận xét:* `podCIDR` được kubeadm gán khi Node join cluster (`--pod-network-cidr=10.244.0.0/16`). flanneld đọc field này để biết mình phụ trách subnet nào.

2. Xem annotation mà flanneld ghi vào Node (public IP và VTEP MAC):
   ```bash
   kubectl get node worker1 -o jsonpath='{.metadata.annotations}' | python3 -m json.tool
   ```
   *Bạn sẽ thấy:*
   ```json
   {
     "flannel.alpha.coreos.com/backend-data": "{\"VNI\":1,\"VtepMAC\":\"xx:xx:xx:xx:xx:xx\"}",
     "flannel.alpha.coreos.com/backend-type": "vxlan",
     "flannel.alpha.coreos.com/kube-subnet-manager": "true",
     "flannel.alpha.coreos.com/public-ip": "192.168.64.11"
   }
   ```
   *Nhận xét:* flanneld các Node khác watch annotation này để biết VTEP MAC và IP vật lý của `worker1` → từ đó cập nhật FDB của chính mình.

---

## 🔬 Thí nghiệm 2: Đọc subnet.env — "Hợp đồng" giữa flanneld và CNI plugin

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Đọc file `subnet.env` — đây là file giao tiếp quan trọng nhất giữa flanneld và CNI bridge plugin:
   ```bash
   cat /run/flannel/subnet.env
   ```
   *Kết quả:*
   ```
   FLANNEL_NETWORK=10.244.0.0/16
   FLANNEL_SUBNET=10.244.1.1/24
   FLANNEL_MTU=1450
   FLANNEL_IPMASQ=true
   ```
   *Giải nghĩa:*
   - `FLANNEL_SUBNET=10.244.1.1/24`: CNI plugin sẽ cấp IP cho Pod trong range này
   - `FLANNEL_MTU=1450`: Bridge và Pod sẽ dùng MTU này (thay vì 1500 mặc định)
   - `FLANNEL_IPMASQ=true`: Kích hoạt masquerade khi Pod traffic ra ngoài cluster

2. Xem CNI conflist — config mà kubelet đọc khi cần cắm mạng cho Pod:
   ```bash
   cat /etc/cni/net.d/10-flannel.conflist
   ```
   *Nhận xét:* Bạn sẽ thấy `"type": "flannel"` — đây là CNI plugin binary sẽ đọc `subnet.env` và delegate xuống `bridge` plugin.

---

## 🕵️‍♂️ Thí nghiệm 3: Phân tích FDB và ARP — "Bản đồ" 3 bước của VTEP

Vẫn ở `worker1`, trace đường đi của packet từ pod-a đến pod-b (trên worker2):

1. **Bước 1 — Route:** Subnet của worker2 đi qua interface nào?
   ```bash
   ip route show | grep 10.244
   ```
   *Bạn sẽ thấy:*
   ```
   10.244.0.0/24 via 10.244.0.0 dev flannel.1   ← về controlplane
   10.244.1.0/24 dev cni0                        ← local pods
   10.244.2.0/24 via 10.244.2.0 dev flannel.1   ← về worker2
   ```
   *Nhận xét:* Để đến `10.244.2.7` (pod-b), kernel forward ra `flannel.1` với next-hop `10.244.2.0`.

2. **Bước 2 — ARP:** IP `10.244.2.0` (VTEP gateway của worker2) có MAC là gì?
   ```bash
   ip neigh show dev flannel.1
   ```
   *Bạn sẽ thấy:*
   ```
   10.244.0.0 lladdr <mac-controlplane> PERMANENT
   10.244.2.0 lladdr <mac-worker2>      PERMANENT
   ```
   *Nhận xét:* Đây là ARP static entries mà flanneld cài vào, map VTEP gateway IP → VTEP MAC của Node kia.

3. **Bước 3 — FDB:** MAC của VTEP worker2 tương ứng Node IP nào?
   ```bash
   bridge fdb show dev flannel.1
   ```
   *Bạn sẽ thấy:*
   ```
   <mac-controlplane> dst 192.168.64.10 self permanent
   <mac-worker2>      dst 192.168.64.12 self permanent
   ```
   *Nhận xét:* Kernel biết gửi UDP VXLAN packet đến `192.168.64.12` — đây là IP vật lý của `worker2`.

4. Tóm tắt luồng 3 bước:
   ```
   10.244.2.7 → Route: via 10.244.2.0 dev flannel.1
              → ARP:   10.244.2.0 = <mac-worker2>
              → FDB:   <mac-worker2> → dst 192.168.64.12
              → UDP 8472 packet gửi đến 192.168.64.12
   ```

---

## 🔬 Thí nghiệm 4: Quan sát log flanneld khi cluster thay đổi

### 🎯 Mục tiêu

Chứng minh rằng **flanneld hoạt động theo mô hình event-driven**: nó liên tục lắng nghe (watch) Kubernetes API, và **chỉ** phản ứng khi có thay đổi thực sự về trạng thái node/subnet. Không có controller nào polling định kỳ — đây là điểm khác biệt cốt lõi của kiến trúc Kubernetes.

### 📖 Lý thuyết nền: Kubernetes Watch API

```
flanneld                     kube-apiserver                  etcd
   │                               │                            │
   │── GET /api/v1/nodes?watch=true ──▶│                            │
   │                               │◀── Watch stream (keep-alive) ──│
   │                               │                            │
   │     [node worker2 changes]    │                            │
   │◀── MODIFIED event ────────────│                            │
   │                               │                            │
   │  → update route table         │                            │
   │  → update ARP/FDB             │                            │
   │  → log "Handling add subnet"  │                            │
```

`flanneld` mở **một kết nối HTTP streaming duy nhất** đến API server. Mọi thay đổi về node được đẩy xuống ngay lập tức — không cần polling.

---

### 🧪 Các bước thực hành

**Trên `controlplane`:**

```bash
multipass shell controlplane
```

#### Bước 1 — Quan sát log baseline của flanneld

```bash
kubectl -n kube-flannel logs daemonset/kube-flannel-ds --since=5m \
  | grep -E "subnet|Handling|Adding|Updating"
```

Expected output (luôn xuất hiện 2 dòng header trước nội dung log):
```
Found 3 pods, using pod/kube-flannel-ds-km75p
Defaulted container "kube-flannel" out of: kube-flannel, install-cni-plugin (init), install-cni (init)
```

**Giải thích 2 dòng header:**

| Dòng | Ý nghĩa |
|---|---|
| `Found 3 pods, using pod/...` | DaemonSet có 3 pods (1 per node). kubectl chọn pod đầu tiên |
| `Defaulted container "kube-flannel"` | Pod này có 3 containers; kubectl mặc định lấy container chính |

> Nếu log trống (chỉ có 2 dòng header, không có nội dung) → cluster đang ổn định, không có thay đổi trong 5 phút qua. **Đây là hành vi bình thường.**

---

#### Bước 2 — Hiểu tại sao "touch annotation" không trigger event

Chạy lệnh ghi đè annotation với **cùng giá trị**:

```bash
kubectl annotate node worker2 \
  flannel.alpha.coreos.com/public-ip=$(kubectl get node worker2 \
  -o jsonpath='{.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip}') \
  --overwrite
```

Expected output:
```
node/worker2 annotated
```

Kiểm tra log ngay sau đó:
```bash
kubectl -n kube-flannel logs daemonset/kube-flannel-ds --since=30s \
  | grep -E "subnet|Handling|Adding|Updating"
```

Expected output: *(chỉ 2 dòng header, không có event nào)*
```
Found 3 pods, using pod/kube-flannel-ds-km75p
Defaulted container "kube-flannel" out of: kube-flannel, install-cni-plugin (init), install-cni (init)
```

> **⚠️ Tại sao log trống?**
> Kubernetes API server so sánh giá trị cũ và mới trước khi lưu. Nếu **resourceVersion** và **giá trị** không đổi, etcd không ghi, watch stream không phát sự kiện, flanneld không nhận được gì.
> → Đây chứng minh Flannel chỉ phản ứng với **thay đổi thực sự**, không bị kích hoạt bởi no-op.

---

#### Bước 3 — Trigger event thực bằng `cordon` + `uncordon`

Mở **2 terminal** vào `controlplane`:

**Terminal 1** — Watch log liên tục:
```bash
kubectl -n kube-flannel logs -f -l app=flannel \
  --max-log-requests=4 | grep -E "subnet|Handling|Adding"
```

**Terminal 2** — Thay đổi trạng thái node thực sự:
```bash
kubectl cordon worker2
sleep 3
kubectl uncordon worker2
```

Expected output Terminal 2:
```
node/worker2 cordoned
node/worker2 uncordoned
```

Expected output Terminal 1 (xuất hiện ngay sau khi `uncordon`):
```
I0518 13:05:42.123456       1 subnet.go:152] "Handling add subnet event" subnet="10.244.2.0/24" network="10.244.0.0/16"
```

> **Tại sao `cordon/uncordon` hoạt động?**
> - `cordon` → set `spec.unschedulable = true` → API server lưu vào etcd → phát MODIFIED event
> - `uncordon` → set `spec.unschedulable = false` → một thay đổi khác → flanneld nhận và reprocess subnet của worker2
> - Không xóa pod nào đang chạy — **an toàn để thử nghiệm**

---

### 📝 Tổng kết thí nghiệm 4

| Hành động | etcd thay đổi? | flanneld nhận event? | Log xuất hiện? |
|---|---|---|---|
| `annotate --overwrite` (cùng giá trị) | ❌ Không | ❌ Không | ❌ Trống |
| `cordon` / `uncordon` | ✅ Có | ✅ Có | ✅ "Handling add subnet event" |

**Kết luận:** flanneld là một **reconciliation loop thuần túy** — chỉ làm việc khi được "thức dậy" bởi sự kiện thực từ API. Đây là lý do Flannel có footprint thấp và không gây tải cho hệ thống khi cluster ổn định.

---

## ✅ Tổng kết

Kiến trúc Flannel là **3 tầng rõ ràng**:
1. **K8s API** làm trung tâm lưu trữ state — không cần etcd riêng
2. **flanneld** watch API, ghi `subnet.env`, cấu hình VTEP/FDB/ARP/routes — đây là "bộ não"
3. **CNI plugin** (bridge binary) đọc `subnet.env` khi Pod tạo, gán IP — đây là "tay chân"

Ba bảng `route → ARP → FDB` trên mỗi Node là cơ chế Flannel tìm đường đến VTEP đích mà không cần bất kỳ controller nào xử lý trong realtime.



Cơm thêm: 

1. max-pods:
```bash
kubectl get node worker1 -o jsonpath='{.status.allocatable.pods}'
# → 110
```
