---
marp: true
theme: default
paginate: true
style: |
  section { font-family: 'Segoe UI', sans-serif; font-size: 22px; background: #0d1021; color: #e2e8f0; }
  h1 { color: #a78bfa; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #34d399; font-size: 1.4em; border-bottom: 2px solid #34d399; padding-bottom: 0.2em; }
  h3 { color: #fbbf24; font-size: 1.1em; }
  code { background: #1a1a35; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1a1a35; border-left: 4px solid #a78bfa; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
  th { background: #2d1b69; color: #e9d5ff; padding: 10px 14px; font-weight: 600; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a2050; color: #e2e8f0; background: #151530; }
  tr:nth-child(even) td { background: #1e1e40; }
  blockquote { border-left: 4px solid #fbbf24; padding-left: 16px; color: #cbd5e1; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  pre .hljs-comment, pre .hljs-meta { color: #7dd3fc; }
  pre .hljs-keyword, pre .hljs-selector-tag { color: #f9a8d4; }
  pre .hljs-string, pre .hljs-attr { color: #86efac; }
  pre .hljs-number, pre .hljs-literal { color: #fde68a; }
  pre .hljs-variable, pre .hljs-template-variable { color: #c4b5fd; }
  pre .hljs-built_in, pre .hljs-name { color: #67e8f9; }
  pre .hljs-subst { color: #e2e8f0; }
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 41
## Cilium Lab 4: WireGuard MTU với Cilium — Hubble show "MTU exceeded" (không cần ping test!)

**Phần 3 — Cilium Labs** · `#lab` `#WireGuard` `#MTU` `#hubble` `#PMTUD`

---

## Tình huống thực tế

```
Cùng scenario như Tập 22 (Calico Lab 3):
"Upload file lớn: hang. File nhỏ: OK."

Với Calico (Tập 22):
  1. Observe symptom: file lớn hang (đợi 5 phút)
  2. Manual: ip link show wireguard.cali → xem MTU
  3. Test DF bit: ping -s 1422 -M do <cross-node-ip>
  4. Interpret: "PING: message too long, mtu=1420"
  5. Fix + verify: repeat ping test
  Time: 15-25 phút

Với Cilium + Hubble:
  1. hubble observe → "MTU exceeded (WireGuard overhead)"
  2. Xem packet size và WireGuard MTU limit ngay trong output
  3. Fix MTU
  4. hubble observe → FORWARDED
  Time: 3-5 phút

→ Hubble thay đổi paradigm: "guessing" → "knowing"
```

---

## WireGuard MTU: Tại sao 1420?

```
Ethernet frame:
  Physical MTU: 1500 bytes
  
WireGuard overhead:
  IP header:         20 bytes
  UDP header:        8 bytes
  WireGuard header:  32 bytes (nonce + auth tag)
  ─────────────────────────────
  Total overhead:    60 bytes

WireGuard MTU = 1500 - 60 = 1440 bytes
(Với IPv6 headers: 1420 bytes)

Cilium default WireGuard MTU: 1420

Nếu set MTU = 1500 trên cilium_wg0:
  Packet lớn gửi với size = 1500
  WireGuard thêm header: 1500 + 60 = 1560 > 1500
  Physical NIC drop hoặc fragment
  → Large file hang, small file OK!
```

---

## Reproduce: Bật WireGuard với MTU sai

```bash
# Enable WireGuard encryption
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard

# Verify WireGuard active
CILIUM_POD=$(kubectl -n kube-system get pod \
  -l k8s-app=cilium -o name | head -1)
kubectl -n kube-system exec -it $CILIUM_POD \
  -- cilium status | grep -i wireguard
# Encryption: Wireguard  ENABLED

# Inject MTU bug trên worker1
multipass exec worker1 -- sudo ip link set \
  cilium_wg0 mtu 1500   # BUG: phải là 1420
```

---

## Reproduce: File lớn fail

```bash
# Deploy cross-node pods
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

# File nhỏ OK
kubectl exec upload-client -- bash -c \
  "dd if=/dev/urandom bs=512K count=1 | nc -w 5 $SERVER_IP 9999"
# Exit: 0 ✅

# File lớn HANG
timeout 10 kubectl exec upload-client -- bash -c \
  "dd if=/dev/urandom bs=1M count=5 | nc -w 30 $SERVER_IP 9999"
# Exit: 124 (timeout!) ← Confirmed bug
```

---

## Debug với Hubble: Không cần ping test!

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
sleep 2

# Start Hubble observer
hubble observe \
  --from-pod default/upload-client \
  --follow &

# Trigger large file transfer
kubectl exec upload-client -- bash -c \
  "dd if=/dev/urandom bs=1M count=5 | nc -w 30 $SERVER_IP 9999" &

# Hubble output (trong vài giây):
# default/upload-client → default/upload-server:9999
# DROPPED  MTU exceeded (WireGuard overhead)
# Packet size: 1500, WireGuard MTU: 1420

# → Root cause ngay lập tức!
# → Không cần ping -M do, không cần ip link show
```

---

## Fix và Verify

```bash
# Fix: Correct MTU trực tiếp (faster for lab)
multipass exec worker1 -- sudo ip link set \
  cilium_wg0 mtu 1420

# Verify MTU fixed
multipass exec worker1 -- ip link show cilium_wg0
# cilium_wg0: mtu 1420  ✅

# Test large file lại
kubectl exec upload-client -- bash -c \
  "dd if=/dev/urandom bs=1M count=5 | nc -w 30 $SERVER_IP 9999"
# 5+0 records out ← Thành công!

# Hubble confirm:
# upload-client → upload-server:9999  FORWARDED ✅

# Production fix: Helm upgrade
# helm upgrade cilium cilium/cilium \
#   --set encryption.wireguard.mtu=1420
```

---

## Calico vs Cilium: MTU debug comparison

| Aspect | Calico (Tập 22) | Cilium + Hubble |
| :--- | :--- | :--- |
| Drop reason | Silent drop | "MTU exceeded (WireGuard overhead)" |
| Cần ping test? | Bắt buộc | Không cần |
| Biết packet size? | Phải đo thủ công | Hubble show ngay |
| Automation? | Khó | `hubble observe --output json \| jq` |
| Time to root cause | 15-25 phút | 3-5 phút |

```
Key insight:
  Calico: "silent drop" → phải reproduce + infer
  Cilium: "labeled drop" → reason + packet size ngay
  
  "MTU exceeded" = packet lớn hơn WireGuard MTU
  → Fix: giảm MTU của cilium_wg0 xuống 1420
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Enable WireGuard với MTU sai, debug bằng Hubble

Chúng ta sẽ thực hành:

1. **Enable WireGuard** trong Cilium + inject MTU bug (set cilium_wg0 MTU = 1500).
2. **Reproduce:** deploy cross-node pods, thấy small file OK nhưng large file timeout.
3. **Hubble debug:** `hubble observe` → "MTU exceeded (WireGuard overhead)" xuất hiện ngay.
4. **Fix MTU:** set cilium_wg0 mtu 1420 → verify large file success.
5. **So sánh vs Calico:** không cần ping test, root cause ngay trong 3-5 phút.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo (Tập 42):** So sánh 3 CNI — Flannel vs Calico vs Cilium, bảng đánh giá toàn diện.
