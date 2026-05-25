# Lab Tập 6: Cài đặt, Quan sát Flannel CNI & Giải mã Kiến trúc Định tuyến L2/L3 (VXLAN Mode)

Trong bài lab này, chúng ta sẽ bắt đầu bằng một cụm Kubernetes trắng (chưa có CNI) để thấy rõ sự bế tắc của các Pod khi không có định tuyến cross-node. Sau đó, chúng ta sẽ cài đặt Flannel và đi sâu giải phẫu cấu trúc định tuyến tĩnh gồm 3 bảng **Route $\rightarrow$ ARP $\rightarrow$ FDB** ở Kernel Space. Cuối cùng, chúng ta sẽ thực hành **giả lập 6 sự cố mạng kinh điển** thường gặp nhất trong môi trường Production để xem tận mắt và tự tay sửa chữa.

---

## 🧭 Kiến thức nền tảng: Flannel trong hệ sinh thái CNI

*(Tập 2 đã học về veth pair + cni0 bridge. Tập 5 đã học về CNI lifecycle. Đây là phần ôn nhanh trước khi thực hành.)*

Flow CNI của Flannel khi kubelet tạo Pod:

```
kubelet → /etc/cni/net.d/10-flannel.conflist
        → flannel CNI binary (/opt/cni/bin/flannel)
        → delegate bridge plugin  (tạo veth pair, gắn vào cni0)
        → delegate host-local IPAM (cấp IP từ /run/flannel/subnet.env)
```

Điểm khác biệt lớn nhất: Flannel bổ sung tầng **Overlay VXLAN** — gói tin đi ra từ Pod được đóng gói trong UDP packet và truyền qua interface ảo `flannel.1` (VTEP), cho phép các Pod liên lạc chéo Node mà không cần thay đổi hạ tầng mạng vật lý của bạn.

### 📐 Mô hình kiến trúc mạng L2/L3 trên một Node:

```
                    +---------------------------------------------+
                    |                 HOST NODE                   |
                    |                                             |
                    |   +------------------+                      |
                    |   |   POD NAMESPACE  |                      |
                    |   |                  |                      |
                    |   |   +----------+   |                      |
                    |   |   |   eth0   |   |  (IP: 10.244.X.Y/24) |
                    |   +---+----+-----+---+                      |
                    |            |                                |
                    |      veth pair (L2 Virtual Wire)            |
                    |            |                                |
                    |   +---+----+-----+---+                      |
                    |   |   |  vethXXX |   |                      |
                    |   |   +----+-----+   |                      |
                    |   |        |         |                      |
                    |   |   +----+-----+   |                      |
                    |   |   |   cni0   |   |  (Linux Bridge)      |
                    |   |   | (10.244. |   |  (Gateway IP:        |
                    |   |   |  X.1/24) |   |   10.244.X.1)        |
                    |   |   +----+-----+   |                      |
                    |   |        |         |                      |
                    |   +--------+---------+                      |
                    |            |                                |
                    |            | (Kernel Routing)               |
                    |            v                                |
                    |     +--------------+                        |
                    |     |  flannel.1   |    (VTEP - VXLAN ID 1) |
                    |     +------+-------+                        |
                    |            |                                |
                    |            v                                |
                    |      +-----------+                          |
                    |      |   eth0    |      (Physical Interface)|
                    |      +-----+-----+      (Host IP: 192.168.64.11)
                    +------------|--------------------------------+
                                 |
                                 v (UDP Packet on Port 8472 chéo Node)
                              To Network
```

---

## 🛠 Yêu cầu chuẩn bị
- Cụm Kubernetes 3 node (controlplane, worker1, worker2) dựng từ Tập 00.
- **Nếu cụm đang cài sẵn Flannel từ Tập 1**: Bạn có thể chạy script dọn dẹp `./reset-lab.sh` ở thư mục `tap-00-setup-lab` và dựng lại cụm trắng để trải nghiệm từ đầu.

---

## 🔬 Thí nghiệm 1: Quan sát Cluster khi KHÔNG có Flannel

Giả sử bạn đang có một cụm trắng (chưa cài đặt CNI).

1. SSH vào `controlplane`:
   ```bash
   multipass shell controlplane
   ```

2. Kiểm tra trạng thái Nodes:
   ```bash
   kubectl get nodes
   ```
   *Nhận xét:* Các Nodes ở trạng thái `NotReady`. Nếu mô tả kỹ node (`kubectl describe node controlplane`), bạn sẽ thấy lỗi: `NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized`.

3. Kiểm tra bảng định tuyến trên `worker1` (mở terminal mới):
   ```bash
   multipass shell worker1
   ip route show
   ```
   *Nhận xét:* Không hề có các route chỉ đường cho dải mạng Pod (ví dụ `10.244.x.x`). Các card mạng ảo như `cni0` hay `flannel.1` hoàn toàn chưa tồn tại.

---

## 🚀 Thí nghiệm 2: Cài đặt Flannel và quan sát sự thay đổi

**Trên Terminal đang SSH vào `controlplane`:**

1. Cài đặt Flannel CNI (phiên bản mới nhất):
   ```bash
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

2. Theo dõi trạng thái Cluster cho đến khi các node chuyển sang `Ready`:
   ```bash
   watch kubectl get nodes
   ```
   *(Nhấn Ctrl+C để thoát)*

**Trên Terminal đang SSH vào `worker1`:**

3. Quan sát các card mạng ảo mới xuất hiện:
   ```bash
   ip link show
   ```
   *Nhận xét:* Bạn sẽ thấy sự xuất hiện của `cni0` (bridge cho các local Pods) và `flannel.1` (VTEP phục vụ cho việc bọc gói tin VXLAN).

---

## 🔬 Thí nghiệm 3: Đọc subnet allocation từ K8s API

flanneld không dùng etcd riêng — nó đọc trực tiếp thông tin từ K8s API server.

**SSH vào `controlplane`:**

1. Xem `podCIDR` được cấp cho từng Node — đây là dữ liệu flanneld đọc để biết subnet nào thuộc về Node nào:
   ```bash
   kubectl get nodes -o custom-columns='NAME:.metadata.name,PODCIDR:.spec.podCIDR,IP:.status.addresses[0].address'
   ```
   *Kết quả mong đợi:*
   ```
   NAME           PODCIDR          IP
   controlplane   10.244.0.0/24    192.168.64.10
   worker1        10.244.1.0/24    192.168.64.11
   worker2        10.244.2.0/24    192.168.64.12
   ```

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
   *Nhận xét:* Tiến trình `flanneld` trên các Node khác sẽ liên tục lắng nghe (watch) các annotation này để cập nhật FDB và bảng ARP tĩnh của chúng.

---

## 🔬 Thí nghiệm 4: Đọc subnet.env — "Hợp đồng" giữa flanneld và CNI plugin

**SSH vào `worker1`:**

```bash
multipass shell worker1
```

1. Đọc file `/run/flannel/subnet.env` — đây là file giao tiếp quan trọng nhất giữa tiến trình `flanneld` (tầng điều khiển) và CNI bridge plugin (tầng thực thi):
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

2. Xem CNI conflist — cấu hình mạng mà `kubelet` đọc khi cần cắm mạng cho Pod:
   ```bash
   cat /etc/cni/net.d/10-flannel.conflist
   ```
   *Nhận xét:* Bạn sẽ thấy `"type": "flannel"` — đây là CNI plugin binary. Bản chất binary này không trực tiếp tạo ra veth pair mà nó sẽ đọc `/run/flannel/subnet.env` và gọi (delegate) tiếp xuống plugin `bridge` của CNI để hoàn tất công việc.

---

## 🕵️‍♂️ Thí nghiệm 5: Phân tích FDB và ARP — "Bản đồ" 3 bước của VTEP

Vẫn ở `worker1`, trace đường đi của packet từ pod-a đến pod-b (trên worker2):

1. **Bước 1 — Route:** Kiểm tra bảng định tuyến của Host:
   ```bash
   ip route show | grep 10.244
   ```
   *Bạn sẽ thấy:*
   ```
   10.244.2.0/24 via 10.244.2.0 dev flannel.1 onlink
   ```
   *Nhận xét:* Để đến bất kỳ Pod nào có IP dạng `10.244.2.X`, kernel phải gửi qua card ảo `flannel.1` với next-hop IP là `10.244.2.0` (VTEP IP của Worker 2).

2. **Bước 2 — ARP:** Tra cứu MAC của next-hop `10.244.2.0`:
   ```bash
   ip neigh show dev flannel.1
   ```
   *Bạn sẽ thấy:*
   ```
   10.244.2.0 lladdr <mac-worker2-vtep> PERMANENT
   ```
   *Nhận xét:* Đây là ARP tĩnh (PERMANENT) do `flanneld` cài đặt vào kernel. Nhờ đó, kernel biết chính xác MAC đích của inner frame.

3. **Bước 3 — FDB:** Tra cứu Node vật lý tương ứng với MAC của VTEP Worker 2:
   ```bash
   bridge fdb show dev flannel.1
   ```
   *Bạn sẽ thấy:*
   ```
   <mac-worker2-vtep> dst 192.168.64.12 self permanent
   ```
   *Nhận xét:* Kernel biết gửi gói tin UDP VXLAN đã đóng gói tới địa chỉ IP vật lý `192.168.64.12` của Worker 2.

**💡 Bonus — Xem flanneld cập nhật bảng này real-time:**

Mở 2 terminal song song. Terminal 1 theo dõi log flanneld, Terminal 2 restart DaemonSet để ép sync lại toàn bộ state:
```bash
# Terminal 1
kubectl logs -n kube-flannel -l app=flannel -c kube-flannel -f --tail=5

# Terminal 2
kubectl rollout restart ds kube-flannel-ds -n kube-flannel
```
*Quan sát:* Bạn sẽ thấy log in `Received added/modified event for node` cho từng Node — bằng chứng flanneld watch K8s API và tự động sync FDB/ARP.

---

## 🌐 Thí nghiệm 6: Kiểm chứng kết nối Cross-Node

**Trên Terminal đang SSH vào `controlplane`:**

1. Khởi tạo 2 Pod nằm trên 2 Worker khác nhau:
   ```bash
   kubectl run pod-a --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker1"}}' -- sleep infinity
   kubectl run pod-b --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker2"}}' -- sleep infinity
   ```

2. Chờ 2 Pod chạy và lấy IP của chúng:
   ```bash
   kubectl wait --for=condition=Ready pod/pod-a pod/pod-b --timeout=60s
   kubectl get pods -o wide
   ```
   *Giả sử IP của Pod B là `10.244.2.X`.*

3. Đứng từ `pod-a`, thực hiện lệnh `ping` sang IP của `pod-b`:
   ```bash
   kubectl exec pod-a -- ping -c 3 <IP_CỦA_POD_B>
   ```
   *Kết quả:* Ping thành công rực rỡ! Gói tin đi ra từ `pod-a` chui qua `cni0`, được kernel định tuyến vào `flannel.1` để đóng gói thành UDP packet (cổng 8472) rồi chuyển qua mạng vật lý đến `worker2`, tại đây nó được tháo băng và gửi tới `pod-b`.

---

## 💥 Thực hành Khắc phục Sự cố (Troubleshooting)

Để hiểu sâu sắc và "xem tận mắt" các sự cố mạng này hoạt động ra sao, chúng ta sẽ tự tay **giả lập (simulate)** từng lỗi trên cluster và tiến hành sửa chữa nó.

---

### 🔍 Sự cố 1: Flannel Pod rơi vào `CrashLoopBackOff` do nhận diện sai Interface Vật lý

#### 🛠️ Bước 1: Kịch bản giả lập sự cố (Tái hiện lỗi)
Chúng sẽ sửa cấu hình DaemonSet Flannel, ép nó quét một interface mạng ảo không tồn tại:
1. Đứng ở `controlplane`, mở cấu hình DaemonSet Flannel:
   ```bash
   kubectl edit daemonset kube-flannel-ds -n kube-flannel
   ```
2. Tìm đến phần `args` của container `kube-flannel` (khoảng dòng 45), bổ sung tham số chọn sai interface:
   ```yaml
   args:
   - --ip-masq
   - --kube-subnet-mgr
   - --iface=eth99  # Ép chọn card mạng không tồn tại!
   ```
3. Lưu lại và thoát (`:wq` trong vi).

#### 🕵️‍♂️ Bước 2: Quan sát thực tế lỗi (Xem tận mắt)
1. Kiểm tra trạng thái của các Pod Flannel:
   ```bash
   kubectl get pods -n kube-flannel
   ```
   *Bạn sẽ thấy:* Các Pod `kube-flannel-ds-xxxx` liên tục bị khởi động lại với trạng thái `CrashLoopBackOff`.
2. Kiểm tra log:
   ```bash
   kubectl logs -n kube-flannel daemonset/kube-flannel-ds
   ```
   *Bạn sẽ nhìn thấy dòng báo lỗi:* `Failed to find any interface with target address`.

#### 🛡️ Bước 3: Cách khắc phục & Sửa chữa
1. Mở lại file cấu hình DaemonSet:
   ```bash
   kubectl edit daemonset kube-flannel-ds -n kube-flannel
   ```
2. Sửa dòng `--iface=eth99` thành card đúng của môi trường (`eth1`) hoặc xóa hẳn dòng đó đi để Flannel tự động quét tìm card chính:
   ```yaml
   args:
   - --ip-masq
   - --kube-subnet-mgr
   - --iface=eth1
   ```
3. Lưu lại và các Pod sẽ hoạt động `Running` ổn định trở lại.

---

### 🔍 Sự cố 2: Node kẹt ở trạng thái `NotReady` do thiếu cấu hình CNI

#### 🛠️ Bước 1: Kịch bản giả lập sự cố (Tái hiện lỗi)
1. SSH vào `worker1`:
   ```bash
   multipass shell worker1
   ```
2. Cố ý di chuyển (sao lưu) tạm thời file cấu hình CNI của Flannel ra thư mục khác:
   ```bash
   sudo mv /etc/cni/net.d/10-flannel.conflist /tmp/10-flannel.conflist.bak
   ```

#### 🕵️‍♂️ Bước 2: Quan sát thực tế lỗi (Xem tận mắt)
1. Đứng ở `controlplane`, kiểm tra trạng thái Node:
   ```bash
   kubectl get nodes
   ```
   *Bạn sẽ thấy:* Chờ khoảng 10 - 20 giây, trạng thái của `worker1` lập tức chuyển từ `Ready` sang **`NotReady`**!
2. Xem nguyên nhân lỗi ghi trong log hệ thống của Node `worker1`:
   ```bash
   kubectl describe node worker1
   ```

> [!NOTE]
> **❓ Thử thách suy ngẫm (Review Questions):**
> 
> *   **Câu hỏi A (Định tuyến):** Trong lúc `worker1` bị kẹt ở trạng thái **`NotReady`** do mất file cấu hình CNI, nếu bạn thực hiện ping từ `pod-b` sang `pod-a` (đang chạy trên `worker1`), bạn sẽ ngạc nhiên thấy **ping vẫn thông suốt 100%!** Tại sao lại như vậy?
> *   **Câu hỏi B (Vòng đời dọn dẹp):** Nếu ta cố tình chạy lệnh xóa `pod-a` khi node `worker1` đang `NotReady` do thiếu cấu hình CNI, tại sao `pod-a` lại bị kẹt ở trạng thái **`Terminating`** vĩnh viễn, và chỉ biến mất sạch sẽ ngay lập tức khi file CNI được khôi phục về chỗ cũ?
> 
> *👉 Hãy phân tích sự phân tách giữa Kubelet (Control Plane) và Linux Kernel (Data Plane). Xem lời giải thích cặn kẽ và chuyên sâu cho cả 2 câu hỏi tại file [0-questions.md](../0-questions.md).*

#### 🛡️ Bước 3: Cách khắc phục & Sửa chữa
1. Quay lại terminal đang SSH trên `worker1`, khôi phục lại file cấu hình CNI về đúng vị trí:
   ```bash
   sudo mv /tmp/10-flannel.conflist.bak /etc/cni/net.d/10-flannel.conflist
   ```
2. Node `worker1` tự động phục hồi và chuyển sang trạng thái **`Ready`** chỉ sau 5 - 10 giây!

---

### 🔍 Sự cố 3: Ping chéo node bị Timeout (Tường lửa chặn cổng UDP 8472)

#### 🛠️ Bước 1: Kịch bản giả lập sự cố (Tái hiện lỗi)

*(⚠️ **Lưu ý thực tế:** Vì `pod-a` đã bị xóa hoàn tất ngay sau khi khôi phục CNI ở Sự cố 2, đứng từ terminal của `controlplane`, bạn hãy chạy lệnh tạo lại `pod-a` trước khi thực hiện kịch bản này):*
```bash
kubectl run pod-a --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker1"}}' -- sleep infinity
kubectl wait --for=condition=Ready pod/pod-a --timeout=60s
```

1. SSH vào `worker2` (Node chứa `pod-b`):
   ```bash
   multipass shell worker2
   ```
2. Thiết lập một rule chặn bằng `iptables` để block cổng nhận UDP 8472:
   ```bash
   sudo iptables -A INPUT -p udp --dport 8472 -j DROP
   ```

#### 🕵️‍♂️ Bước 2: Quan sát thực tế lỗi (Xem tận mắt)
1. Đứng từ `pod-a` trên `controlplane`, gửi ping sang `pod-b` liên tục:
   ```bash
   kubectl exec pod-a -- ping -c 10 <IP_CỦA_POD_B>
   ```
   *Kết quả:* Ping bị treo cứng (Timeout 100% loss).
2. Kiểm tra bằng `tcpdump` trên card `eth0` của `worker2`:
   ```bash
   sudo tcpdump -i eth0 -n udp port 8472
   ```
   *Bạn sẽ thấy:* Gói tin UDP VXLAN đi tới từ `worker1` vẫn xuất hiện trên `tcpdump`, nhưng do tường lửa DROP nên Kernel không phản hồi.

#### 🛡️ Bước 3: Cách khắc phục & Sửa chữa
1. Quay lại terminal trên `worker2`, xóa bỏ rule chặn tường lửa:
   ```bash
   sudo iptables -D INPUT -p udp --dport 8472 -j DROP
   ```
2. Gói tin ping sẽ thông suốt trở lại ngay lập tức!

---

### 🔍 Sự cố 4: Lỗi kẹt hoặc cạn kiệt dải IP Pod trong Host-Local IPAM

#### 🕵️‍♂️ Bước 1: Nhận diện lỗi
Khi deploy Pod mới trên `worker1`, Pod bị kẹt ở trạng thái `ContainerCreating`. Xem mô tả sự cố bằng lệnh `kubectl describe pod` thấy lỗi:
```text
failed to allocate for range 0: no IP addresses available in range
```

#### 🛡️ Bước 2: Cách khắc phục & Giải quyết
1. SSH vào `worker1`, kiểm tra thư mục lưu trữ lease IPAM của Flannel:
   ```bash
   ls -la /var/lib/cni/networks/flannel/
   ```
   Mỗi file trong thư mục này đại diện cho một IP đã được cấp phát. Nội dung file chứa Container ID.
2. Đối chiếu Container ID với các container thực tế đang chạy trên Node:
   ```bash
   sudo crictl ps -a
   ```
3. Nếu phát hiện file IP chứa Container ID của một container đã chết từ lâu nhưng chưa được dọn dẹp (do kubelet crash đột ngột), tiến hành xóa file đó đi để giải phóng IP về pool:
   ```bash
   sudo rm /var/lib/cni/networks/flannel/<IP_BỊ_KẸT>
   ```

---

## ✅ Tổng kết

Kiến trúc Flannel được chia làm 3 tầng cực kỳ rõ ràng:
1. **K8s API**: Nơi lưu trữ trạng thái tập trung (Node annotations và `podCIDR`).
2. **flanneld**: "Bộ não" watch API, setup `flannel.1` interface, điền các bảng ARP/FDB/Route, ghi `subnet.env`.
3. **CNI bridge plugin**: "Tay chân" đọc `subnet.env`, tạo veth pair và gán IP cho Pod.
