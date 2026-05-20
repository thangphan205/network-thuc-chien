# Lab Tập 8: VXLAN Backend — Soi packet thực tế với tcpdump

Tập này dùng `tcpdump` để "soi" bên trong VXLAN tunnel và xác minh toàn bộ lý thuyết 50-byte overhead bằng thực nghiệm. Sau lab này bạn sẽ thấy được cả inner và outer IP header trong cùng một packet.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Flannel VXLAN đang chạy (Tập 6-7).
- `pod-a` trên `worker1`, `pod-b` trên `worker2` (nếu chưa có, tạo lại từ Tập 6).

---

## 🔬 Thí nghiệm 1: Verify cấu hình VTEP & Bắt VXLAN traffic với tcpdump

**Mở 2 terminal song song:**

**Terminal 1 — SSH vào `worker1` (nơi chạy pod-a):**
```bash
multipass shell worker1
```

1. **Verify cấu hình VTEP đầy đủ** trên interface `flannel.1` trước khi bắt gói tin:
   ```bash
   ip -d link show flannel.1
   ```
   *Output sẽ có:*
   ```
   flannel.1: ... mtu 1450 ...
       vxlan id 1 local 192.168.64.11 dev eth0 srcport 0 0 dstport 8472 nolearning ttl inherit ageing 300 udpcsum noudp6zerocsumtx noudp6zerocsumrx
   ```
   *Các thông số cấu hình quan trọng cần lưu ý:*
   - `vxlan id 1` — VNI = 1 (mặc định của Flannel).
   - `local 192.168.64.11` — IP vật lý của Node này (sẽ là outer source IP khi đóng gói).
   - `dstport 8472` — UDP port mà kernel Linux dùng cho VXLAN (Flannel dùng cổng chuẩn này thay vì IANA 4789).

2. **Bắt đầu nghe traffic VXLAN** trên physical interface:
   ```bash
   sudo tcpdump -i eth0 -n udp port 8472 -v
   ```
   *(Lệnh treo, chờ traffic)*

**Terminal 2 — SSH vào `controlplane`, tạo traffic cross-node:**
```bash
multipass shell controlplane

# Lấy IP của pod-b trước
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
echo "Pod B IP: $POD_B_IP"

# Gửi 5 ICMP ping từ pod-a sang pod-b (cross-node)
kubectl exec pod-a -- ping -c 5 $POD_B_IP
```

**Quay lại Terminal 1**, bạn sẽ thấy output như sau:
```
12:34:56.123456 IP 192.168.64.11.49152 > 192.168.64.12.8472: VXLAN, flags [I] (0x08), vni 1
    IP 10.244.1.5 > 10.244.2.7: ICMP echo request, id 42, seq 1, length 64
```

*Nhận xét:*
- **Dòng 1 (Outer):** Node-to-Node: `192.168.64.11` (worker1) → `192.168.64.12` (worker2), UDP port 8472, VNI=1. Khớp hoàn toàn với cấu hình VTEP ta vừa xem!
- **Dòng 2 (Inner):** Pod-to-Pod: `10.244.1.5` (pod-a) → `10.244.2.7` (pod-b), ICMP.

Bấm `Ctrl+C` để dừng tcpdump.

---

## 🔬 Thí nghiệm 2: Chứng minh 50 bytes overhead bằng length field

Vẫn trên `worker1`, dùng flag `-v` để tcpdump in ra **length** của cả outer và inner packet:

```bash
sudo tcpdump -i eth0 -n udp port 8472 -v -c 2
```

Tạo traffic từ Terminal 2:
```bash
kubectl exec pod-a -- ping -c 2 $POD_B_IP
```

Output sẽ trông như này:
```
IP 192.168.252.40.47834 > 192.168.252.41.8472: VXLAN, flags [I] (0x08), vni 1
  IP 10.244.1.3 > 10.244.2.4: ICMP echo request, id 42006, seq 1, length 64
    (tos 0x0, ttl 64, id 60887, offset 0, flags [DF], proto UDP (17), length 134)
```

**Đọc 2 con số `length` trong output:**

```
length 134   ← outer IP packet (node → node, bao gồm toàn bộ VXLAN tunnel)
length 64    ← inner ICMP payload (ping data thuần)
```

Nhưng để so sánh đúng, cần dùng **inner IP total length** = 84 bytes (inner IP header 20 + ICMP 64):

```
Outer IP length  :  134 bytes  (toàn bộ packet trên wire, không tính outer Ethernet)
Inner IP length  :   84 bytes  (ICMP packet bên trong tunnel)
                    ─────────
Overhead         :   50 bytes  ← đây là VXLAN tunnel overhead
```

Phân rã 50 bytes:

```
Outer IP header   20 bytes
Outer UDP header   8 bytes
VXLAN header       8 bytes
Inner Ethernet    14 bytes
               ──────────
Total overhead    50 bytes  →  MTU Pod = 1500 - 50 = 1450 bytes
```

Notes: So sánh hiển thị length khi bắt gói tin bằng tcpdump và wireshark.

---

## 🔬 Thí nghiệm 3: Đo MTU thực tế bằng DF bit (Don't Fragment)

**Trên `controlplane`:**

1. Ping với size tối đa không bị fragment từ bên trong pod-a:
   ```bash
   # MTU bên trong Pod = 1450 bytes
   # Ping overhead: 20 (IP) + 8 (ICMP) = 28 bytes
   # Payload tối đa = 1450 - 28 = 1422 bytes

   kubectl exec pod-a -- ping -c 3 -s 1422 -M do $POD_B_IP
   ```
   *Kết quả:* `3 packets transmitted, 3 received` ✅ — đúng giới hạn.

2. Vượt 1 byte:
   ```bash
   kubectl exec pod-a -- ping -c 1 -s 1423 -M do $POD_B_IP
   ```
   *Kết quả:* `ping: local error: message too long, mtu=1450` ❌ — kernel từ chối.

3. So sánh MTU trên các interfaces:
   
   **Trên `controlplane` (nơi có `kubectl`):**
   ```bash
   # MTU của Pod eth0
   kubectl exec pod-a -- ip link show eth0
   # eth0: mtu 1450  ← Flannel set
   ```

   **Trên `worker1` (SSH vào `worker1` trước bằng `multipass shell worker1`):**
   ```bash
   # MTU của cni0 bridge trên worker1
   ip link show cni0
   # cni0: mtu 1450  ← Khớp với Pod

   # MTU của VTEP
   ip link show flannel.1
   # flannel.1: mtu 1450  ← Khớp

   # MTU của physical interface
   ip link show eth0
   # eth0: mtu 1500  ← Physical, đủ chỗ cho VXLAN header + payload
   ```

---

## 🔬 Thí nghiệm 4: Benchmark throughput ở VXLAN mode với iperf3

**Trên `controlplane`:**

1. Deploy iperf3 server trên `worker2`:
   ```bash
   kubectl run iperf3-server \
     --image=networkstatic/iperf3 \
     --overrides='{"spec":{"nodeName":"worker2"}}' \
     -- iperf3 -s
   kubectl expose pod iperf3-server --port=5201 --type=ClusterIP
   kubectl wait --for=condition=Ready pod/iperf3-server --timeout=60s
   ```

2. Test throughput từ `worker1` (cross-node) — **VXLAN mode hiện tại:**
   ```bash
   IPERF_IP=$(kubectl get svc iperf3-server -o jsonpath='{.spec.clusterIP}')

   kubectl run iperf3-client \
     --image=networkstatic/iperf3 \
     --overrides='{"spec":{"nodeName":"worker1"}}' \
     --restart=Never \
     -- iperf3 -c $IPERF_IP -t 15 -P 4

   kubectl wait --for=condition=Ready pod/iperf3-client --timeout=60s
   kubectl logs iperf3-client | tail -5
   ```
   *Ghi lại kết quả throughput (Gbits/sec) ở VXLAN mode để làm baseline so sánh ở Tập 9.*

3. Test latency:
   ```bash
   kubectl exec iperf3-client -- ping -c 50 $IPERF_IP 2>/dev/null | tail -2
   ```

4. Dọn dẹp:
   ```bash
   kubectl delete pod iperf3-client iperf3-server
   kubectl delete svc iperf3-server
   ```

---

## ✅ Tổng kết

Bài lab chứng minh bằng thực nghiệm:
1. **VXLAN = UDP tunnel**: Outer packet chứa Node IP, inner packet chứa Pod IP — tcpdump thấy cả hai.
2. **50 bytes overhead = thực**: Tính từ góc nhìn inner IP (Outer IP + UDP + VXLAN + Inner Eth). Trong hex dump thực tế với `-XX`, inner IP nằm ở byte 64 vì tcpdump capture từ L2 (có thêm 14 bytes outer Ethernet). MTU 1450 được enforce bởi kernel.
3. **Tự động tối ưu TCP MSS**: Vì MTU của interface ảo (`eth0` trong Pod) được Flannel cấu hình là 1450, hệ điều hành inside Pod tự đàm phán TCP MSS = 1410 trong quá trình bắt tay 3 bước. Điều này giúp gói tin TCP luôn vừa vặn trong VXLAN tunnel mà không cần tới rule MSS Clamping thủ công trong iptables.
4. **Physical MTU (1500) >= Pod MTU (1450) + VXLAN overhead (50)** — đây là điều kiện tiên quyết để VXLAN hoạt động.
