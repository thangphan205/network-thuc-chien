# Lab Tập 24: Lab 3 — WireGuard MTU Black Hole

Tập này tái hiện và sửa lỗi PMTUD (Path MTU Discovery) Black Hole: truyền nhận file dung lượng nhỏ hoạt động bình thường, nhưng truyền file lớn qua kết nối chéo Node bị treo (hang) không phản hồi.

### Sơ đồ cơ chế phình kích thước gói tin qua lớp mã hóa WireGuard:
```mermaid
graph TD
  subgraph Packet_Overhead [Cơ chế phình kích thước gói tin và PMTUD Silent Drop]
    PodPacket["1. Gói tin từ Pod A (MTU 1500, DF=1)<br/>[ IPv4 (20B) ] [ TCP (20B) ] [ Payload (1460B) ]<br/>Tổng size = 1500 Bytes"]
    
    WGPacket["2. Đi qua lớp mã hóa WireGuard<br/>[ Outer IPv4 (20B) ] [ WG Header (60B) ] [ Encrypted Payload & Headers (1480B) ]<br/>Tổng size = 1560 Bytes"]
    
    NodeInterface["3. Cổng mạng vật lý Node (MTU 1500)<br/>Kích thước 1560B > MTU 1500 & DF=1<br/>(Không được phân mảnh)"]
    
    SilentDrop["4. SILENT DROP !<br/>Gói tin bị chặn đứng hoàn toàn, không phản hồi.<br/>Ứng dụng bị treo (Connection Hang)."]

    PodPacket --> WGPacket
    WGPacket --> NodeInterface
    NodeInterface --> SilentDrop
  end
  
  classDef default fill:#151530,stroke:#2a2050,color:#e2e8f0;
  class SilentDrop fill:#2d080a,stroke:#f87171,color:#ff8a8a;
```

---

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 11.
- Ubuntu 26.04 — WireGuard kernel built-in.
- `pod-a` trên `worker1`, hoặc sẽ tạo trong lab này.

---

## 🔬 Thí nghiệm 1: Setup WireGuard với MTU sai

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Bật WireGuard:
   ```bash
   kubectl patch felixconfiguration default \
     --type merge \
     --patch '{"spec": {"wireguardEnabled": true}}'
   ```

2. **Cố tình set MTU sai** (quá cao — đây là bug cần reproduce):
   ```bash
   kubectl patch felixconfiguration default \
     --type merge \
     --patch '{"spec": {"wireguardMTU": 1500}}'
   ```

3. Chờ Calico reload:
   ```bash
   kubectl -n calico-system rollout status daemonset/calico-node
   ```

4. Verify WireGuard interface xuất hiện với MTU sai:
   ```bash
   multipass exec worker1 -- ip link show wireguard.cali
   # wireguard.cali: mtu 1500  ← Sai! (phải là 1420)
   ```

5. Deploy upload-client trên worker1 và upload-server trên worker2:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: upload-client
   spec:
     nodeName: worker1
     containers:
     - name: c
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: upload-server
   spec:
     nodeName: worker2
     containers:
     - name: s
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "9999"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: upload-server-local
   spec:
     nodeName: worker1
     containers:
     - name: s
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "9998"]
   EOF
   kubectl wait --for=condition=Ready pod/upload-client pod/upload-server pod/upload-server-local --timeout=90s
   ```

6. Ghi lại IPs:
   ```bash
   SERVER_IP=$(kubectl get pod upload-server -o jsonpath='{.status.podIP}')
   LOCAL_IP=$(kubectl get pod upload-server-local -o jsonpath='{.status.podIP}')
   echo "Cross-node server: $SERVER_IP"
   echo "Same-node server: $LOCAL_IP"
   ```

---

## 💥 Thí nghiệm 2: Reproduce — File nhỏ OK, file lớn hang

**Trên `controlplane`:**

1. File nhỏ (512KB) cross-node — **OK:**
   ```bash
   kubectl exec upload-client -- bash -c "
     dd if=/dev/urandom bs=512K count=1 2>/dev/null | nc -w 5 $SERVER_IP 9999
     echo 'Small file (cross-node): '$?
   "
   # Small file (cross-node): 0  ✅ Success
   ```

2. File lớn (5MB) cross-node — **HANG:**
   ```bash
   kubectl exec upload-client -- bash -c "
     timeout 10 bash -c 'dd if=/dev/urandom bs=1M count=5 2>/dev/null | nc $SERVER_IP 9999'
     echo 'Large file (cross-node) exit: '$?
   "
   # Large file (cross-node) exit: 124  ← Timeout! Bị hang
   ```

3. File lớn (5MB) **cùng node** — **OK** (không qua WireGuard):
   ```bash
   kubectl exec upload-client -- bash -c "
     dd if=/dev/urandom bs=1M count=5 2>/dev/null | nc -w 10 $LOCAL_IP 9998
     echo 'Large file (same-node) exit: '$?
   "
   # Large file (same-node) exit: 0  ✅ OK! Cùng node không qua WireGuard
   ```

   *Kết luận:* Pattern rõ ràng: cross-node + large file = fail. Same-node = OK. → WireGuard MTU issue.

---

## 🔬 Thí nghiệm 3: Debug — Xác định MTU thực tế

**Trên `controlplane`:**

1. Kiểm tra MTU trên interfaces:
   ```bash
   kubectl exec upload-client -- ip link show eth0
   # eth0: mtu 1500  ← Pod interface MTU (sai với WireGuard)

   multipass exec worker1 -- ip link show wireguard.cali
   # wireguard.cali: mtu 1500  ← Sai! Quá cao
   ```

2. Test với DF bit để tìm MTU thực tế:
   ```bash
   # MTU 1420 với WireGuard overhead
   # Ping với payload 1400 bytes (+ 20 IP + 8 ICMP = 1428 total, nên OK)
   kubectl exec upload-client -- ping -c 2 -s 1400 -M do $SERVER_IP
   # OK

   # Ping với payload 1440 bytes (1440 + 28 = 1468 > 1420 → fail)
   kubectl exec upload-client -- ping -c 1 -s 1440 -M do $SERVER_IP
   # ping: local error: message too long, mtu=1420
   # ← Kernel biết MTU thực = 1420 dù interface nói 1500!
   ```

3. Hiểu cơ chế:
   ```
   WireGuard interface MTU = 1500 (sai)
   Kernel gửi TCP segment = 1460 bytes
   WireGuard overhead = 80 bytes → 1540 bytes
   Physical eth0 MTU = 1500 → 1540 > 1500
   DF bit = 1 → không fragment
   → SILENT DROP (không có ICMP fragmentation needed)
   → TCP sender không biết → tiếp tục gửi → hang
   ```

---

## 🔬 Thí nghiệm 4: Fix và verify

**Trên `controlplane`:**

1. **Fix MTU đúng:**
   ```bash
   kubectl patch felixconfiguration default \
     --type merge \
     --patch '{"spec": {"wireguardMTU": 1420}}'
   ```

2. Chờ Calico reload:
   ```bash
   kubectl -n calico-system rollout status daemonset/calico-node
   ```

3. Verify MTU đã đúng:
   ```bash
   multipass exec worker1 -- ip link show wireguard.cali
   # wireguard.cali: mtu 1420  ✅

   kubectl exec upload-client -- ip link show eth0
   # eth0: mtu 1420  ← Pod MTU cũng được update!
   ```

4. Test lại — file lớn cross-node:
   ```bash
   kubectl exec upload-client -- bash -c "
     dd if=/dev/urandom bs=1M count=5 2>/dev/null | nc -w 30 $SERVER_IP 9999
     echo 'Large file (cross-node after fix) exit: '$?
   "
   # Large file (cross-node after fix) exit: 0  ✅ THÀNH CÔNG!
   ```

5. Thêm MSS Clamping để bảo vệ thêm:
   ```bash
   kubectl patch felixconfiguration default \
     --type merge \
     --patch '{"spec": {"wireguardMssClamp": 1380}}'

   # Verify iptables rule
   multipass exec worker1 -- sudo iptables -t mangle -L | grep TCPMSS
   # TCPMSS  tcp  -- ... TCPMSS clamp to 1380  ← Auto cài bởi Calico
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod upload-client upload-server upload-server-local

# Tắt WireGuard và trả cấu hình Felix MTU/MSS về lại mặc định (null) để tránh ảnh hưởng các bài lab sau
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardEnabled": false, "wireguardMTU": null, "wireguardMssClamp": null}}'
```

---

## ✅ Tổng kết

1. **Pattern nhận biết:** Cross-node + large file fail + same-node OK = MTU/WireGuard issue.
2. **Diagnose:** `ping -M do -s 1440 <cross-node-ip>` → kernel báo MTU thực tế (`mtu=1420`).
3. **Fix:** `wireguardMTU: 1420` (không phải 1500). Physical 1500 − WireGuard overhead ~80 = 1420.
4. **MSS Clamping:** Extra bảo vệ — ép TCP negotiate MSS ≤ 1380. Calico tự cài iptables mangle rule.
