# Lab Tập 19: Full Mesh vs Route Reflector

Tập này cấu hình Route Reflector để giảm BGP sessions từ n*(n-1)/2 xuống ~n.

### Sơ đồ so sánh kiến trúc Peering giữa các Node:

#### 1. Kiến trúc BGP Full Mesh (Mặc định)
```mermaid
graph TD
  subgraph Full_Mesh [Kiến trúc Full Mesh: n*(n-1)/2 Sessions]
    Node1[Node 1: ControlPlane] <-->|BGP Session 1| Node2[Node 2: Worker1]
    Node2 <-->|BGP Session 2| Node3[Node 3: Worker2]
    Node3 <-->|BGP Session 3| Node1
  end
```

#### 2. Kiến trúc BGP Route Reflector
```mermaid
graph TD
  subgraph Route_Reflector_Peering [Kiến trúc Route Reflector: ~n Sessions]
    RR[Node 1: ControlPlane - Route Reflector]
    Node2[Node 2: Worker1]
    Node3[Node 3: Worker2]
    
    Node2 <-->|BGP Session 1| RR
    Node3 <-->|BGP Session 2| RR
    
    note["Giữa Worker1 và Worker2 KHÔNG tự thiết lập session.<br/>Routes được học chéo thông qua bộ chuyển tiếp RR."]
    classDef default fill:#151530,stroke:#2a2050,color:#e2e8f0;
    class RR fill:#2d1b69,stroke:#a78bfa,color:#fff;
  end
```

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 18 đang chạy BGP mode.
- `calicoctl` đã cài.

---

## 🔬 Thí nghiệm 1: Xem Full Mesh BGP hiện tại

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Xem BGP sessions trên từng node:
   ```bash
   calicoctl node status
   # Với 3 nodes: mỗi node peer với 2 nodes khác = 3 sessions tổng
   ```

2. Verify full mesh enabled:
   ```bash
   calicoctl get bgpconfiguration default -o yaml | grep nodeToNodeMeshEnabled
   # nodeToNodeMeshEnabled: true
   ```

3. Tính toán: với 3 nodes hiện tại:
   ```
   3 × (3-1) / 2 = 3 sessions total
   ```
   *Nhận xét:* Với 100 nodes sẽ là 4950 sessions — không scale được.

---

## 🔬 Thí nghiệm 2: Cấu hình Route Reflector

**Trên `controlplane`:**

1. Bước 1 — Tắt full mesh:
   ```bash
   calicoctl patch bgpconfiguration default \
     --patch '{"spec": {"nodeToNodeMeshEnabled": false}}'
   ```

2. Bước 2 — Label `controlplane` làm Route Reflector:
   ```bash
   kubectl label node controlplane calico-route-reflector=true
   ```

3. Bước 3 — Annotate RR node với cluster ID:
   ```bash
   calicoctl patch node controlplane \
     --patch '{"spec": {"bgp": {"routeReflectorClusterID": "1.0.0.1"}}}'
   ```

4. Bước 4 — Tạo BGPPeer: regular nodes → RR:
   ```bash
   calicoctl apply -f - <<'EOF'
   apiVersion: projectcalico.org/v3
   kind: BGPPeer
   metadata:
     name: peer-to-rr
   spec:
     nodeSelector: "!has(calico-route-reflector)"
     peerSelector: "has(calico-route-reflector)"
   EOF
   ```

5. Bước 5 — RR peer với RR (nếu có nhiều RR):
   ```bash
   calicoctl apply -f - <<'EOF'
   apiVersion: projectcalico.org/v3
   kind: BGPPeer
   metadata:
     name: rr-to-rr
   spec:
     nodeSelector: "has(calico-route-reflector)"
     peerSelector: "has(calico-route-reflector)"
   EOF
   ```

---

## 🔬 Thí nghiệm 3: Verify BGP sessions giảm

**Trên `controlplane`:**

1. Xem sessions trên worker1 (chỉ peer với RR):
   ```bash
   calicoctl node status
   # PEER ADDRESS  | PEER TYPE      | STATE
   # 192.168.64.10 | node specific  | up   ← Chỉ peer với controlplane (RR)
   # (không còn peer trực tiếp với worker2!)
   ```

2. Xem sessions trên controlplane (RR — peer với tất cả):
   ```bash
   # Controlplane peer với cả worker1 và worker2
   # PEER ADDRESS  | PEER TYPE      | STATE
   # 192.168.64.11 | node specific  | up   ← worker1
   # 192.168.64.12 | node specific  | up   ← worker2
   ```

3. Đếm tổng sessions:
   ```
   Trước (full mesh, 3 nodes): 3 sessions
   Sau (Route Reflector):       2 sessions (worker1→RR + worker2→RR)
   
   Với 100 nodes:
   Trước: 4950 sessions
   Sau:   ~100 sessions (mỗi node chỉ peer với RR)
   ```

---

## 🔬 Thí nghiệm 4: Test connectivity vẫn OK

**Trên `controlplane`:**

1. Test Pod-to-Pod cross-node vẫn hoạt động:
   ```bash
   POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
   kubectl exec pod-a -- ping -c 5 $POD_B_IP
   # 5 packets transmitted, 5 received ✅
   # Route đi qua RR nhưng connectivity không bị ảnh hưởng
   ```

2. Xem routing table — routes vẫn đầy đủ:
   ```bash
   multipass exec worker1 -- ip route show | grep 10.244
   # 10.244.0.0/26 via 192.168.64.10 dev eth0  ← controlplane
   # 10.244.1.0/26 dev cni0                    ← local
   # 10.244.2.0/26 via 192.168.64.12 dev eth0  ← worker2 (learned via RR)
   ```
   *Nhận xét:* Route đến worker2 subnet vẫn tồn tại, được học qua RR thay vì direct peer.

---

## 🧹 Khôi phục full mesh (chuẩn bị cho Tập 20)

```bash
# Nếu muốn về full mesh cho Tập 20 (WireGuard):
calicoctl patch bgpconfiguration default \
  --patch '{"spec": {"nodeToNodeMeshEnabled": true}}'

kubectl label node controlplane calico-route-reflector-
calicoctl delete bgppeer peer-to-rr rr-to-rr 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **Full Mesh = n*(n-1)/2 sessions:** Scale kém — 100 nodes = 4950 sessions.
2. **Route Reflector = ~n sessions:** Mỗi regular node chỉ peer với RR — sessions giảm tuyến tính.
3. **4 bước cấu hình RR:** Tắt mesh → label RR node → annotate cluster ID → tạo BGPPeer selector.
4. **Connectivity không đổi:** Routes vẫn được học đầy đủ thông qua RR — Pod-to-Pod hoạt động bình thường.
5. **Production HA:** Luôn dùng ít nhất 2 RR nodes để tránh single point of failure.
