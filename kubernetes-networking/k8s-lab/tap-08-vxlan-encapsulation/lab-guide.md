# Lab Tập 8: VXLAN Backend — Soi packet thực tế với tcpdump

Tập này dùng `tcpdump` để "soi" bên trong VXLAN tunnel và xác minh toàn bộ lý thuyết 50-byte overhead bằng thực nghiệm. Sau lab này bạn sẽ thấy được cả inner và outer IP header trong cùng một packet.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Flannel VXLAN đang chạy (Tập 6-7).
- `pod-a` trên `worker1`, `pod-b` trên `worker2` (nếu chưa có, tạo lại từ Tập 6).

---

## 🔬 Thí nghiệm 1: Bắt VXLAN traffic với tcpdump

Flannel VXLAN dùng UDP port 8472 (Linux default — khác chuẩn IANA 4789).

**Mở 2 terminal song song:**

**Terminal 1 — SSH vào `worker1` (nơi chạy pod-a), bắt đầu nghe:**
```bash
multipass shell worker1
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
- **Dòng 1 (Outer):** Node-to-Node: `192.168.64.11` (worker1) → `192.168.64.12` (worker2), UDP port 8472, VNI=1
- **Dòng 2 (Inner):** Pod-to-Pod: `10.244.1.5` (pod-a) → `10.244.2.7` (pod-b), ICMP

Bấm `Ctrl+C` để dừng tcpdump.

---

## 🔬 Thí nghiệm 2: Xem raw bytes — xác nhận 50 bytes header

Vẫn trên `worker1`:

1. Bắt với flag `-XX` để thấy hex dump:
   ```bash
   sudo tcpdump -i eth0 -n udp port 8472 -XX -c 3 &
   TCPDUMP_PID=$!
   ```

2. Trên Terminal 2, tạo thêm traffic:
   ```bash
   kubectl exec pod-a -- ping -c 3 $POD_B_IP
   ```

3. Dừng tcpdump và phân tích:
   ```bash
   kill $TCPDUMP_PID
   ```

   *Trong hex dump, đếm offset của từng header:*
   ```
   0x0000  [14 bytes Outer Ethernet]
   0x000e  [20 bytes Outer IP]
   0x0022  [8 bytes  UDP]
   0x002a  [8 bytes  VXLAN]       ← tổng outer headers: 50 bytes
   0x0032  [14 bytes Inner Ethernet]
   0x0040  [20 bytes Inner IP]
   0x0054  [ICMP payload bắt đầu từ đây]
   ```

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
   ```bash
   # MTU của Pod eth0
   kubectl exec pod-a -- ip link show eth0
   # eth0: mtu 1450  ← Flannel set

   # MTU của cni0 bridge trên worker1
   multipass exec worker1 -- ip link show cni0
   # cni0: mtu 1450  ← Khớp với Pod

   # MTU của VTEP
   multipass exec worker1 -- ip link show flannel.1
   # flannel.1: mtu 1450  ← Khớp

   # MTU của physical interface
   multipass exec worker1 -- ip link show eth0
   # eth0: mtu 1500  ← Physical, đủ chỗ cho VXLAN header + payload
   ```

---

## 🔬 Thí nghiệm 4: Verify MSS Clamping của Flannel

**Trên `worker1`:**

```bash
multipass shell worker1
```

1. Xem rule MSS Clamping trong iptables mangle table:
   ```bash
   sudo iptables -t mangle -L -v | grep -A2 TCPMSS
   ```
   *Bạn sẽ thấy:*
   ```
   TCPMSS  tcp  --  ...  PHYSDEV match --physdev-is-bridged  tcp flags:SYN,RST/SYN TCPMSS clamp to PMTU
   ```
   *Nhận xét:* Rule này tự động ép MSS = PMTU (1450) trên mọi TCP SYN packet đi qua bridge, ngăn việc negotiate MSS cao hơn MTU thực tế.

2. Verify VTEP details đầy đủ:
   ```bash
   ip -d link show flannel.1
   ```
   *Output sẽ có:*
   ```
   flannel.1: ... mtu 1450 ...
       vxlan id 1 local 192.168.64.11 dev eth0 srcport 0 0 dstport 8472 nolearning ttl inherit ageing 300 udpcsum noudp6zerocsumtx noudp6zerocsumrx
   ```
   *Các thông số quan trọng:*
   - `vxlan id 1` — VNI = 1
   - `local 192.168.64.11` — IP của Node này
   - `dstport 8472` — UDP port VXLAN

---

## ✅ Tổng kết

Bài lab chứng minh bằng thực nghiệm:
1. **VXLAN = UDP tunnel**: Outer packet chứa Node IP, inner packet chứa Pod IP — tcpdump thấy cả hai.
2. **50 bytes overhead = thực**: Đếm được trong hex dump, MTU 1450 được enforce bởi kernel.
3. **MSS Clamping**: Flannel cài iptables rule để TCP tự điều chỉnh segment size — không cần app thay đổi gì.
4. **Physical MTU (1500) >= Pod MTU (1450) + VXLAN overhead (50)** — đây là điều kiện tiên quyết để VXLAN hoạt động.
