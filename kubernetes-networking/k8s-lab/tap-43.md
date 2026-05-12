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

# Tập 43
## Cilium Lab 4: WireGuard MTU với Cilium — Hubble show "MTU exceeded" (không cần ping test!)

**Phần 3 — Cilium Labs** · `#lab` `#WireGuard` `#MTU` `#hubble` `#PMTUD`

---

## Tình huống thực tế

```
Cùng scenario như Tập 24 (Calico Lab 3):
  "Upload file lớn: hang. File nhỏ: OK."

Với Calico debug:
  Phải dùng ping -M do để reproduce
  Đọc MTU từ ip link show
  Manual trial-and-error
  → 15-30 phút

Với Cilium + Hubble:
  hubble observe → "MTU exceeded" xuất hiện ngay!
  Không cần ping test!
  Không cần check MTU thủ công!
  → 2-5 phút

Lab này: so sánh trực tiếp debug speed
```

---

## Lab Setup: Bật WireGuard với MTU sai

```bash
multipass shell k8s-master

# Enable WireGuard trong Cilium
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard

# Verify WireGuard active
kubectl -n kube-system exec -it \
  $(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1) \
  -- cilium status | grep -i wireguard
# Encryption: Wireguard  ENABLED  ✅

# Giả lập MTU sai bằng cách set MTU quá cao
multipass exec k8s-worker1 -- sudo ip link set \
  cilium_wg0 mtu 1500    # BUG: Phải là ~1420
```

---

## Setup: Pods cross-node

```bash
# Deploy 2 pods trên 2 node khác nhau
kubectl run upload-client \
  --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker1"}}' \
  -- sleep infinity

kubectl run upload-server \
  --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker2"}}' \
  -- nc -lk -p 9999

kubectl wait --for=condition=Ready \
  pod/upload-client pod/upload-server --timeout=60s

SERVER_IP=$(kubectl get pod upload-server \
  -o jsonpath='{.status.podIP}')
```

---

## Reproduce: File lớn fail

```bash
# File nhỏ: OK
kubectl exec upload-client -- bash -c "
  dd if=/dev/urandom bs=512K count=1 | nc -w 5 $SERVER_IP 9999
  echo 'Small: \$?'
"
# Small: 0  ✅

# File lớn: HANG
kubectl exec upload-client -- bash -c "
  timeout 10 bash -c \
    'dd if=/dev/urandom bs=1M count=5 | nc \$SERVER_IP 9999'
  echo 'Large: \$?'
"
# Large: 124  ← Timeout!
```

---

## Debug với Hubble: Không cần ping test!

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Start Hubble observer
hubble observe \
  --from-pod default/upload-client \
  --follow &

# Trigger large file transfer
kubectl exec upload-client -- bash -c "
  dd if=/dev/urandom bs=1M count=5 | nc -w 30 $SERVER_IP 9999
" &>/dev/null &

# Hubble output (xuất hiện trong vài giây):
# default/upload-client → default/upload-server:9999
# DROPPED  MTU exceeded (WireGuard overhead)
# Packet size: 1500, WireGuard MTU: 1420
# → Root cause ngay lập tức!

# Với Calico: không có message này!
# Phải manual: ping -M do, ip link show, trial-error
```

---

## Fix và Verify

```bash
# Fix MTU
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set MTU=1420    # Set đúng MTU

# Hoặc direct patch (faster for lab):
multipass exec k8s-worker1 -- sudo ip link set \
  cilium_wg0 mtu 1420

# Verify MTU fix
multipass exec k8s-worker1 -- ip link show cilium_wg0
# cilium_wg0: mtu 1420  ✅

# Test lại: file lớn bây giờ OK
kubectl exec upload-client -- bash -c "
  dd if=/dev/urandom bs=1M count=5 | nc -w 30 $SERVER_IP 9999
  echo 'Large file: \$?'
"
# Large file: 0  ✅ THÀNH CÔNG!

# Hubble confirm:
# upload-client → upload-server:9999  FORWARDED ✅
```

---

## Calico vs Cilium: MTU debug comparison

```
Calico MTU debug (Tập 24):
  1. Observe symptom: large file hang (5 phút wait)
  2. Check MTU: ip link show wireguard.cali (thủ công)
  3. Test DF bit: ping -s 1422 -M do <cross-node-ip>
  4. Interpret: "PING: message too long, mtu=1420"
  5. Try fix: kubectl patch felixconfiguration...
  6. Verify: repeat ping test
  Total: 15-25 phút

Cilium MTU debug:
  1. Observe symptom: large file hang (1 phút)
  2. hubble observe → "MTU exceeded (WireGuard overhead)"
     → Root cause rõ ràng
  3. Fix MTU setting
  4. hubble observe → FORWARDED
  Total: 3-5 phút

Sự khác biệt: "silent drop" → "labeled drop with reason"
```

---

## Hubble MTU drop reason: Chi tiết hơn

```bash
# Hubble JSON output cho MTU drop:
hubble observe \
  --from-pod default/upload-client \
  --verdict DROPPED \
  --output json | jq '
    .flow | {
      src: .source.pod_name,
      dst: .destination.pod_name,
      verdict: .verdict,
      drop_reason: .drop_reason_desc,
      pkt_size: .Summary
    }
  '

# Output:
# {
#   "src": "upload-client",
#   "dst": "upload-server",
#   "verdict": "DROPPED",
#   "drop_reason": "MTU exceeded",
#   "pkt_size": "1500 bytes (WireGuard max: 1420)"
# }

# Đủ thông tin để fix ngay:
# - Biết MTU hiện tại: 1500
# - Biết giới hạn: 1420
# → Fix: set WireGuard MTU = 1420
```

---

## Key Takeaways

**Cilium vs Calico cho MTU debugging:**

| Aspect | Calico | Cilium + Hubble |
| :--- | :--- | :--- |
| Drop reason visible? | ❌ Silent drop | ✅ "MTU exceeded" |
| Cần ping test? | ✅ Required | ❌ Không cần |
| Time to root cause | 15-25 phút | 3-5 phút |
| Automation possible? | Khó | `hubble observe --output json` |

```
Cilium không chỉ fix MTU nhanh hơn —
nó thay đổi paradigm từ "guessing" sang "knowing"

Hubble drop reasons:
  "Policy denied"    → Label/policy issue
  "MTU exceeded"     → MTU misconfiguration  
  "No route"         → Routing issue
  "Connection reset" → TCP RST từ destination
  
Mỗi reason → immediate action item!
```

> **Tập tiếp theo (Tập 44): So sánh 3 CNI — Flannel vs Calico vs Cilium, bảng đánh giá toàn diện.**
