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

# Tập 24
## Lab 3: WireGuard MTU & PMTUD Black Hole — File nhỏ ok, file lớn fail

**Phần 2 — Calico Labs** · `#WireGuard` `#MTU` `#PMTUD` `#lab` `#BlackHole`

---

## Tình huống thực tế

```
Ticket từ Backend team:
"Upload file ảnh < 1MB: OK.
 Upload file video > 5MB: hang mãi, không xong.
 Chỉ xảy ra khi upload qua Service vào Pod trên Node khác.
 Cùng Node thì OK.
 WireGuard đang bật trên cluster."

Dấu hiệu đặc trưng: "cross-node", "large file", "WireGuard"
→ Nghi ngờ MTU issue ngay lập tức
```

---

## Lab Setup: Bật WireGuard với MTU sai

```bash
multipass shell k8s-master

# Bật WireGuard encryption
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardEnabled": true}}'

# Cố tình set MTU SAI (quá cao) để reproduce bug
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardMTU": 1500}}'   # BUG: Phải là 1420!

# Verify WireGuard lên nhưng MTU sai
multipass exec k8s-worker1 -- ip link show wireguard.cali
# wireguard.cali: mtu 1500  ← Sai! Quá cao

# Tạo Pods trên 2 Node khác nhau
kubectl run upload-client --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker1"}}' -- sleep infinity
kubectl run upload-server --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker2"}}' \
  -- nc -lk -p 9999

kubectl wait --for=condition=Ready pod/upload-client pod/upload-server --timeout=60s
SERVER_IP=$(kubectl get pod upload-server -o jsonpath='{.status.podIP}')
```

---

## Reproduce: File nhỏ OK, file lớn fail

```bash
# File nhỏ: OK
kubectl exec upload-client -- bash -c "
  dd if=/dev/urandom bs=512K count=1 | nc -w 5 $SERVER_IP 9999
  echo 'Small file: \$?'
"
# Small file: 0  ✅ (success)

# File lớn: HANG
kubectl exec upload-client -- bash -c "
  timeout 10 bash -c 'dd if=/dev/urandom bs=1M count=5 | nc $SERVER_IP 9999'
  echo 'Large file exit: \$?'
"
# Large file exit: 124  ← Timeout! Bị hang

# Test trên CÙNG Node (cùng node không qua WireGuard)
kubectl run upload-server-local --image=nicolaka/netshoot \
  --overrides='{"spec":{"nodeName":"k8s-worker1"}}' \
  -- nc -lk -p 9998
SERVER_LOCAL_IP=$(kubectl get pod upload-server-local -o jsonpath='{.status.podIP}')
kubectl exec upload-client -- bash -c "
  dd if=/dev/urandom bs=1M count=5 | nc -w 10 $SERVER_LOCAL_IP 9998
  echo 'Same-node exit: \$?'
"
# Same-node exit: 0  ✅ (cùng node = không qua WireGuard = OK!)
```

---

## Debug: Xác định MTU là culprit

```bash
# Kiểm tra MTU trên interfaces
kubectl exec upload-client -- ip link show eth0
# eth0: mtu 1500  ← Pod MTU

multipass exec k8s-worker1 -- ip link show wireguard.cali
# wireguard.cali: mtu 1500  ← Quá cao!

# Test với DF bit (Don't Fragment)
kubectl exec upload-client -- bash -c "
  # Tính size tối đa: MTU 1500 - 20 IP - 8 ICMP = 1472
  # Nhưng WireGuard cần thêm ~80 bytes overhead
  # Nên effective payload limit thực sự là ~1420

  # Thử size 1422 (nên OK nếu không có WireGuard overhead)
  ping -s 1422 -M do -c 3 $SERVER_IP
  echo 'Exit: \$?'
"
# PING: local error: message too long, mtu=1420
# Kernel report: actual MTU = 1420 (WireGuard limit) nhưng interface nói 1500
# → DF bit set + packet > 1420 → SILENT DROP!
```

---

## Fix và Verify

```bash
# Fix: Set MTU đúng cho WireGuard
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardMTU": 1420}}'

# Chờ Felix cập nhật interface
sleep 5

# Verify MTU đã đúng
multipass exec k8s-worker1 -- ip link show wireguard.cali
# wireguard.cali: mtu 1420  ✅

kubectl exec upload-client -- ip link show eth0
# eth0: mtu 1420  ← Pod MTU cũng được update!

# Test lại: file lớn bây giờ OK
kubectl exec upload-client -- bash -c "
  dd if=/dev/urandom bs=1M count=5 | nc -w 30 $SERVER_IP 9999
  echo 'Large file exit: \$?'
"
# Large file exit: 0  ✅ THÀNH CÔNG!

# Thêm MSS Clamping để chắc chắn hơn
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"wireguardMssClamp": 1380}}'
```

---

## Key Lessons

**PMTUD Black Hole pattern:**
```
Symptom: Small files OK, large files fail
         Only fails cross-node (not same-node)
         Hang không có error message rõ ràng

Root cause: 
  MTU interface > Actual effective MTU
  DF bit = 1 (TCP default)
  Packet > effective MTU → SILENT DROP
  Sender không nhận được ICMP "fragmentation needed"
  → Không giảm MSS → tiếp tục gửi packet lớn → hang mãi
```

**Debug checklist:**
```bash
# 1. Compare MTU cross-node vs same-node
ip link show wireguard.cali
ip link show eth0

# 2. Test với DF bit
ping -s 1400 -M do <cross-node-ip>

# 3. Fix MTU
kubectl patch felixconfiguration default \
  --type merge --patch '{"spec":{"wireguardMTU":1420}}'
```

> **Tập tiếp theo:** Lab 4 — Cross-namespace AND/OR bug, Prometheus không scrape được.
