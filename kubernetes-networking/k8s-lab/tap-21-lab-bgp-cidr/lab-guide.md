# Lab Tập 21: Lab 2 — BGP UP nhưng External Server không reach Pod

Tập này debug kịch bản BGP session ESTABLISHED giữa các Node K8s nhưng server ngoài cluster không ping được Pod IP do thiếu thông tin định tuyến.

### Sơ đồ kiến trúc định tuyến: BGP Peering (Production) vs Static Route (Lab Shortcut)

```mermaid
graph TD
  subgraph Production_BGP [1. Giải pháp Production: BGP Peering thực tế]
    Node1[Kubernetes Node 1] <-->|BGP Session / TCP Port 179| ExtRouter[External Router / Server chạy FRR]
    Node1 ---|Quảng bá IP Pool tự động| IPPool[Pod IP Pool: 10.244.0.0/16]
    ExtRouter -->|Tự động học Route qua BGP| RouteDynamic["10.244.0.0/16 via Node 1 IP"]
  end

  subgraph Lab_Static_Route [2. Giải pháp Thực hành trong Lab: Static Route]
    Node2[K8s Node: 192.168.64.10]
    ExtVM[Monitoring VM độc lập]
    ExtVM == Static Route thủ công: sudo ip route add 10.244.0.0/16 via 192.168.64.10 ==> Node2
  end
  
  classDef default fill:#151530,stroke:#2a2050,color:#e2e8f0;
  class ExtRouter,ExtVM fill:#2d1b69,stroke:#a78bfa,color:#fff;
```

---

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico đang chạy BGP mode (từ Tập 16).
- `calicoctl` đã cài.
- Có thể tạo thêm 1 Multipass VM chạy Ubuntu 26.04 để làm external server.

---

## 🔬 Thí nghiệm 1: Verify BGP session và reproduce vấn đề

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Verify cluster đang chạy BGP mode:
   ```bash
   calicoctl get ippool default-ipv4-ippool -o yaml | grep encapsulation
   # encapsulation: None  ← BGP mode (không encapsulation)
   ```
   *Nếu vẫn là VXLAN, chuyển sang BGP trước:*
   ```bash
   calicoctl patch ippool default-ipv4-ippool \
     --patch '{"spec": {"encapsulation": "None", "natOutgoing": true}}'
   ```

2. Verify BGP sessions UP:
   ```bash
   calicoctl node status
   # IPv4 BGP status
   # PEER ADDRESS  | STATE | INFO
   # 192.168.64.11 | up    | Established ← worker1
   # 192.168.64.12 | up    | Established ← worker2
   ```

3. Xem BGPConfiguration hiện tại:
   ```bash
   calicoctl get bgpconfiguration default -o yaml
   # spec:
   #   asNumber: 64512
   #   nodeToNodeMeshEnabled: true
   #   serviceClusterIPs: []  ← Trống! (Trường này dùng để quảng bá dải Service Cluster IP, không phải dải Pod)
   ```

---

## 🔬 Thí nghiệm 2: Simulate external server và verify không reach

**Trên macOS host (Terminal mới):**

1. Tạo Multipass VM để simulate monitoring server:
   ```bash
   multipass launch 26.04 --name monitoring-server \
     --cpus 1 --memory 1G --disk 10G
   ```

2. Ghi lại IP của monitoring-server:
   ```bash
   MONITOR_IP=$(multipass info monitoring-server | grep IPv4 | awk '{print $2}')
   echo "Monitoring server IP: $MONITOR_IP"
   ```

3. Verify monitoring-server **không reach** Pod IP:
   ```bash
   # Lấy Pod IP từ controlplane
   # multipass shell controlplane
   # POD_IP=$(kubectl get pod server -o jsonpath='{.status.podIP}')  (nếu có pod)

   # Deploy test pod nếu chưa có
   multipass shell controlplane
   kubectl run test-pod --image=nicolaka/netshoot -- sleep infinity
   kubectl wait --for=condition=Ready pod/test-pod --timeout=60s
   POD_IP=$(kubectl get pod test-pod -o jsonpath='{.status.podIP}')
   echo "Pod IP: $POD_IP"

   # Từ monitoring-server: ping Pod IP
   multipass exec monitoring-server -- ping -c 3 -W 2 $POD_IP
   # 3 packets transmitted, 0 received ← FAIL
   ```

4. Check routing table trên monitoring-server:
   ```bash
   multipass exec monitoring-server -- ip route show
   # default via 192.168.64.1 dev eth0
   # 192.168.64.0/24 dev eth0
   # ← Không có route 10.244.0.0/16!
   ```
   *Nhận xét:* BGP UP nhưng monitoring-server không nhận route Pod CIDR.

---

## 🔬 Thí nghiệm 3: Debug — Tại sao route không xuất hiện

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. **Hiểu bản chất của BGP Route Advertisement:**
   * Calico **tự động quảng bá** dải IP của Pod (Pod IP Pool) tới tất cả các BGP Peer đã được thiết lập session.
   * Trường `BGPConfiguration.spec.serviceClusterIPs` dùng để quảng bá dải **Service Cluster IP** (để bên ngoài gọi trực tiếp Service VIP không cần NAT), **không được dùng** để quảng bá dải Pod CIDR.

2. **Tại sao `monitoring-server` không nhận được route?**
   * BGP là giao thức chạy trên cổng TCP 179. Để nhận được thông tin định tuyến, các thiết bị phải thiết lập **BGP Session (Peering)** thành công.
   * Máy ảo `monitoring-server` là một VM độc lập, không chạy BGP daemon (như BIRD hay FRR) và không peer với các K8s nodes, nên nó không thể học được route động qua BGP.

3. **Hướng giải quyết:**
   * **Production Approach (Định tuyến động):** Cài đặt BGP daemon (FRR/BIRD) trên monitoring server và thiết lập session BGP (BGPPeer) với các Kubernetes nodes. Calico sẽ tự động đẩy route của Pod và Service sang.
   * **Lab Approach & Hybrid Setup (Định tuyến tĩnh):** Do môi trường lab đơn giản (hoặc trong thực tế với các server không hỗ trợ BGP), ta cấu hình một **Static Route** trên `monitoring-server` trỏ dải Pod CIDR đi qua một trong các node K8s (ControlPlane/Worker).

---

## 🔬 Thí nghiệm 4: Khắc phục sự cố

### 1. Production Design Reference: Cấu hình BGP Peering thực tế (Tham khảo)

Trong môi trường thực tế doanh nghiệp, ta sẽ thiết lập định tuyến động thông qua BGP Peer như sau:

* **Bước A: Tạo tài nguyên BGPPeer trên Kubernetes (Calico):**
  ```yaml
  apiVersion: projectcalico.org/v3
  kind: BGPPeer
  metadata:
    name: peer-monitoring-server
  spec:
    peerIP: 192.168.64.X         # IP của Monitoring Server
    asNumber: 64512              # AS Number của monitoring server
  ```

* **Bước B: Cấu hình FRR/BIRD trên Monitoring Server:**
  Cài đặt FRR và thiết lập router BGP để kết nối tới các K8s node qua TCP 179 để tự động cập nhật bảng định tuyến mỗi khi có Pod mới được tạo.

---

### 2. Lab Solution: Định tuyến tĩnh (Static Route)

Vì máy ảo `monitoring-server` của chúng ta không cài BGP daemon để tránh phức tạp hóa bài lab, ta sẽ thiết lập **Static Route** trỏ qua `controlplane` làm cổng trung chuyển (gateway).

**Trên macOS host hoặc Terminal đang chạy máy ảo `monitoring-server`:**

1. Tìm IP của `controlplane` (BGP router của cụm):
   ```bash
   MASTER_IP=$(multipass info controlplane | grep IPv4 | awk '{print $2}')
   echo "Controlplane IP: $MASTER_IP"
   ```

2. Thêm static route trỏ dải Pod CIDR qua `controlplane` trên `monitoring-server`:
   ```bash
   multipass exec monitoring-server -- sudo ip route add 10.244.0.0/16 via $MASTER_IP
   ```

3. Kiểm tra bảng định tuyến trên `monitoring-server`:
   ```bash
   multipass exec monitoring-server -- ip route show | grep 10.244
   # 10.244.0.0/16 via 192.168.64.X dev eth0   ✅ Route tĩnh đã được thiết lập!
   ```

4. **Verify — Test ping từ external server tới Pod IP:**
   ```bash
   # Từ monitoring-server, ping trực tiếp tới Pod IP
   multipass exec monitoring-server -- ping -c 5 $POD_IP
   
   # 5 packets transmitted, 5 received, 0% packet loss ✅ THÀNH CÔNG!
   ```
   *Kết quả:* Packet được định tuyến chính xác từ `monitoring-server` -> `controlplane` -> `worker node` chạy Pod.

---

## 🧹 Dọn dẹp

```bash
# Trên controlplane
kubectl delete pod test-pod

# Trên macOS host
multipass delete monitoring-server && multipass purge
```

---

## ✅ Tổng kết

1. **BGP Control Plane ≠ BGP Data Plane:** Session BGP ở trạng thái `Established` giữa các K8s node chỉ đảm bảo định tuyến nội bộ cluster. Server bên ngoài muốn học route động bắt buộc phải thiết lập BGP session (BGP Peering) thực sự.
2. **Hiểu đúng `serviceClusterIPs`:** Tham số này chỉ dùng để quảng bá dải **Service Cluster IP** ra ngoài, còn dải **Pod IP Pool** được quảng bá tự động theo cơ chế IPAM của Calico.
3. **Mô hình Hybrid (Static Route):** Định tuyến tĩnh là phương án hoàn hảo, đơn giản và cực kỳ phổ biến trong thực tế cho các máy chủ legacy hoặc các máy chủ giám sát ngoài cluster không hỗ trợ BGP.
