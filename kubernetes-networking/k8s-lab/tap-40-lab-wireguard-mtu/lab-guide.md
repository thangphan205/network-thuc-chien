# Lab Tập 40: Cilium Lab 4 — WireGuard MTU với Cilium, Hubble show "MTU exceeded"

Tập này reproduce và debug WireGuard MTU bug với Cilium: inject MTU sai (1500 thay vì 1420) trên cilium_wg0, file lớn hang, Hubble show "MTU exceeded" ngay — không cần `ping -M do` như Calico (Tập 21).

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy (từ Tập 24).
- Cluster 3 nodes (controlplane, worker1, worker2).
- Hubble relay running.

---

## 🔬 Thực nghiệm 1: Enable WireGuard và inject MTU bug

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Enable WireGuard encryption trong Cilium:
   ```bash
   helm upgrade cilium cilium/cilium \
     --namespace kube-system \
     --reuse-values \
     --set encryption.enabled=true \
     --set encryption.type=wireguard

   # Chờ cilium-agent restart
   kubectl -n kube-system rollout status daemonset/cilium --timeout=120s
   ```

2. Verify WireGuard active:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium status | grep -iE "wireguard|encryption"
   # Encryption:         Wireguard   ENABLED  ✅

   # Xem interface cilium_wg0 trên worker1
   multipass exec worker1 -- ip link show cilium_wg0
   # cilium_wg0: mtu 1420  ← Đây là default đúng
   ```

3. Inject MTU bug: đặt MTU quá cao:
   ```bash
   # BUG: Set MTU = 1500 (physical max) thay vì 1420 (WireGuard max)
   multipass exec worker1 -- sudo ip link set \
     cilium_wg0 mtu 1500

   # Verify bug injected:
   multipass exec worker1 -- ip link show cilium_wg0
   # cilium_wg0: mtu 1500  ← Bug active!

   # Giải thích tại sao bug:
   # WireGuard overhead: IP(20) + UDP(8) + WG header(32) = 60 bytes
   # MTU 1500 → WireGuard packet = 1500 + 60 = 1560 → physical drop!
   ```

---

## 💥 Thực nghiệm 2: Reproduce — File lớn fail, file nhỏ OK

**Trên `controlplane`:**

1. Deploy cross-node pods (upload-client trên worker1, server trên worker2):
   ```bash
   kubectl run upload-client \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker1"}}' \
     -- sleep infinity

   kubectl run upload-server \
     --image=nicolaka/netshoot \
     --overrides='{"spec":{"nodeName":"worker2"}}' \
     -- nc -lk -p 9999

   kubectl wait --for=condition=Ready \
     pod/upload-client pod/upload-server --timeout=60s

   SERVER_IP=$(kubectl get pod upload-server \
     -o jsonpath='{.status.podIP}')
   echo "Server IP: $SERVER_IP"
   ```

2. Test file nhỏ (OK) và file lớn (fail):
   ```bash
   # File nhỏ: 512KB → OK
   kubectl exec upload-client -- bash -c \
     "dd if=/dev/urandom bs=512K count=1 2>/dev/null | nc -w 5 $SERVER_IP 9999
      echo 'Small file exit: $?'"
   # Small file exit: 0 ✅

   # File lớn: 5MB → HANG
   timeout 12 kubectl exec upload-client -- bash -c \
     "dd if=/dev/urandom bs=1M count=5 2>/dev/null | nc -w 30 $SERVER_IP 9999
      echo 'Large file exit: $?'" || echo "TIMEOUT (exit 124)"
   # TIMEOUT (exit 124) ← Confirmed MTU bug!
   ```

---

## 🔬 Thực nghiệm 3: Debug với Hubble — Không cần ping test!

**Trên `controlplane`:**

1. Setup Hubble observer trước khi trigger:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2

   hubble observe \
     --from-pod default/upload-client \
     --follow &
   HUBBLE_PID=$!
   ```

2. Trigger large file transfer và đọc Hubble:
   ```bash
   kubectl exec upload-client -- bash -c \
     "dd if=/dev/urandom bs=1M count=2 2>/dev/null | nc -w 15 $SERVER_IP 9999" &

   sleep 5
   # Hubble output (xuất hiện trong vài giây):
   # default/upload-client → default/upload-server:9999
   # DROPPED  MTU exceeded (WireGuard overhead)
   # Packet size: 1500, WireGuard MTU: 1420
   #
   # → Root cause ngay lập tức!
   # → Không cần: ping -M do, ip link show manual, trial-error
   ```

3. So sánh với Calico MTU debug (Tập 21):
   ```
   Calico debug (15-25 phút):
     1. Wait to confirm hang (5+ phút)
     2. ip link show wireguard.cali → thủ công
     3. ping -s 1422 -M do <cross-node-ip> → test DF bit
     4. "message too long, mtu=1420" → infer root cause
     5. Patch FelixConfiguration → wait convergence
     6. Repeat ping test → verify

   Cilium + Hubble (3-5 phút):
     1. hubble observe → "MTU exceeded (WireGuard overhead)"
        Biết ngay: packet size 1500, limit 1420
     2. Fix MTU
     3. hubble observe → FORWARDED

   Sự khác biệt: "silent drop" → "labeled drop with reason"
   ```

4. Stop observer:
   ```bash
   kill $HUBBLE_PID 2>/dev/null
   ```

---

## 🔬 Thực nghiệm 4: Fix và verify với Hubble realtime

**Trên `controlplane`:**

1. Fix MTU trên worker1:
   ```bash
   # Direct fix (nhanh cho lab)
   multipass exec worker1 -- sudo ip link set \
     cilium_wg0 mtu 1420

   # Verify:
   multipass exec worker1 -- ip link show cilium_wg0
   # cilium_wg0: mtu 1420  ✅
   ```

2. Test large file lại với Hubble confirm:
   ```bash
   hubble observe \
     --from-pod default/upload-client \
     --follow &
   HUBBLE_PID=$!

   # Large file test
   kubectl exec upload-client -- bash -c \
     "dd if=/dev/urandom bs=1M count=5 2>/dev/null | nc -w 30 $SERVER_IP 9999
      echo 'Large file exit: $?'"
   # 5+0 records out
   # Large file exit: 0  ✅ THÀNH CÔNG!

   sleep 2
   # Hubble output:
   # upload-client → upload-server:9999  FORWARDED ✅
   # Không còn DROPPED nào!

   kill $HUBBLE_PID 2>/dev/null
   ```

3. Verify JSON output của Hubble (automation-friendly):
   ```bash
   # Hubble JSON output cho drop reason (khi còn bug):
   # hubble observe \
   #   --from-pod default/upload-client \
   #   --verdict DROPPED \
   #   --output json | jq '
   #     .flow | {
   #       src: .source.pod_name,
   #       dst: .destination.pod_name,
   #       verdict: .verdict,
   #       drop_reason: .drop_reason_desc
   #     }
   #   '
   # Output:
   # {
   #   "src": "upload-client",
   #   "dst": "upload-server",
   #   "verdict": "DROPPED",
   #   "drop_reason": "MTU exceeded"
   # }
   # → Có thể script hóa monitoring!

   pkill -f "port-forward" 2>/dev/null || true
   ```

4. Production fix qua Helm (để persistent sau restart):
   ```bash
   # Production: fix qua Helm upgrade
   # helm upgrade cilium cilium/cilium \
   #   --namespace kube-system \
   #   --reuse-values \
   #   --set encryption.enabled=true \
   #   --set encryption.type=wireguard \
   #   --set tunnel=disabled \
   #   --set autoDirectNodeRoutes=true
   # Cilium sẽ tự set MTU đúng (1420) cho cilium_wg0

   echo "Lab complete!"
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod upload-client upload-server

# Tắt WireGuard encryption (về trạng thái ban đầu)
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=false
kubectl -n kube-system rollout status daemonset/cilium --timeout=120s
```

---

## ✅ Tổng kết

1. **"MTU exceeded" = Hubble killer feature cho MTU debugging:** Cilium BPF ghi nhận chính xác reason và packet size khi drop — không cần `ping -M do` trial-and-error như Calico. Debug time: 3-5 phút vs 15-25 phút.
2. **WireGuard MTU = 1420:** Physical MTU (1500) - WireGuard overhead (60 bytes: IP + UDP + WG header) = 1440, IPv6 thêm overhead = 1420. Cilium default đúng; bug xảy ra khi ai đó manual set MTU cao hơn trên `cilium_wg0`.
3. **Hubble drop reasons cheat sheet:** `"Policy denied"` → Label/policy. `"MTU exceeded"` → MTU misconfiguration. `"No route"` → Routing. `"Connection reset"` → TCP RST. Mỗi reason = immediate action item, không cần guessing.
4. **Automation với JSON output:** `hubble observe --output json | jq '.flow.drop_reason_desc'` có thể script hóa để alert tự động khi xuất hiện MTU drops — impossible với Calico silent drops.
