# Lab Tập 38: Cilium Lab 3 — DNS Egress Policy & toFQDNs trap, External API fail bí ẩn

Tập này debug 2 bugs trong toFQDNs policy: Bug 1 (quên allow DNS port 53) và Bug 2 (stale FQDN cache khi CDN rotate IP). Hubble xác định Bug 1 ngay lập tức; `cilium fqdn cache list` xác định Bug 2.

## 🛠 Yêu cầu chuẩn bị
- Cilium + Hubble đang chạy (từ Tập 23).
- Cluster có internet access từ pods.

---

## 🔬 Thực nghiệm 1: Baseline — Internet access hoạt động

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Deploy payment-service pod:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: payment-service
     labels:
       app: payment-service
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF

   kubectl wait --for=condition=Ready pod/payment-service --timeout=60s
   ```

2. Test internet access ban đầu (không có policy):
   ```bash
   # DNS resolution
   kubectl exec payment-service -- \
     nslookup httpbin.org
   # Server: 10.96.0.10 (coredns)
   # Address: 34.239.x.x

   # HTTP request
   kubectl exec payment-service -- \
     curl -s --max-time 10 http://httpbin.org/ip
   # {"origin": "..."} ← Works!
   ```

---

## 💥 Thực nghiệm 2: Apply policy Bug 1 — Quên allow DNS

**Trên `controlplane`:**

1. Apply policy thiếu DNS rule:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: payment-egress
   spec:
     endpointSelector:
       matchLabels:
         app: payment-service
     egress:
     # BUG: Không có rule cho DNS (port 53)!
     - toFQDNs:
       - matchName: "httpbin.org"
       toPorts:
       - ports:
         - port: "80"
           protocol: TCP
   EOF
   ```

2. Test: connection fail:
   ```bash
   kubectl exec payment-service -- \
     curl -s --max-time 10 http://httpbin.org/ip
   # curl: (6) Could not resolve host: httpbin.org
   # ← DNS resolve fail!
   ```

3. Setup Hubble và xác nhận root cause:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2

   hubble observe \
     --from-pod default/payment-service \
     --verdict DROPPED \
     --follow &
   HUBBLE_PID=$!

   # Trigger request
   kubectl exec payment-service -- \
     curl --max-time 5 http://httpbin.org/ip &>/dev/null

   sleep 2
   # Hubble output:
   # default/payment-service → kube-system/coredns:53
   # DROPPED  Policy denied
   #
   # Root cause ngay: DNS query bị block!
   # toFQDNs không có IP nào để allow
   # → Tất cả connections đều fail

   kill $HUBBLE_PID 2>/dev/null
   ```

---

## 🔬 Thực nghiệm 3: Fix Bug 1 — Add DNS allow rule

**Trên `controlplane`:**

1. Fix: thêm DNS egress rule:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: payment-egress
   spec:
     endpointSelector:
       matchLabels:
         app: payment-service
     egress:
     # Fix: Allow DNS đến kube-dns
     - toEndpoints:
       - matchLabels:
           k8s:io.kubernetes.pod.namespace: kube-system
           k8s-app: kube-dns
       toPorts:
       - ports:
         - port: "53"
           protocol: UDP
         rules:
           dns:
           - matchPattern: "httpbin.org"

     # Allow FQDN traffic
     - toFQDNs:
       - matchName: "httpbin.org"
       toPorts:
       - ports:
         - port: "80"
           protocol: TCP
   EOF
   ```

2. Verify DNS flows với Hubble:
   ```bash
   hubble observe \
     --from-pod default/payment-service \
     --protocol dns \
     --follow &
   HUBBLE_PID=$!

   kubectl exec payment-service -- \
     curl -s --max-time 10 http://httpbin.org/ip
   # {"origin": "..."} ✅ FIXED!

   sleep 2
   # Hubble DNS output:
   # default/payment-service → kube-system/coredns:53
   # DNS Query: httpbin.org
   # FORWARDED ← DNS allowed now!

   kill $HUBBLE_PID 2>/dev/null
   ```

3. Verify Cilium đang track IPs:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod \
     -l k8s-app=cilium -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium fqdn cache list
   # httpbin.org
   #   IPs: 34.239.x.x   ← Cilium tracking này
   #   TTL: 60s remaining
   ```

---

## 🔬 Thực nghiệm 4: Bug 2 — Stale FQDN cache và cách xử lý

**Trên `controlplane`:**

1. Hiểu mechanism của Bug 2:
   ```bash
   # Xem current FQDN cache
   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium fqdn cache list
   # httpbin.org
   #   IPs: 34.239.x.x, 52.201.x.x   ← Cilium track nhiều IPs
   #   TTL: 45s remaining

   # Bug 2 xảy ra khi:
   # 1. CDN rotate → httpbin.org trả về IP mới (ví dụ: 18.xxx.xxx.xxx)
   # 2. App có DNS cache → dùng IP cũ (không có trong fqdn cache)
   # 3. BPF policy: IP cũ không trong allow list → DROP
   # 4. Intermittent: lúc IP match (lucky), lúc không (unlucky)
   ```

2. Simulate stale bằng cách xem multiple IPs:
   ```bash
   # Query nhiều lần để thấy Cilium track nhiều IPs
   for i in $(seq 1 5); do
     kubectl exec payment-service -- \
       curl -s http://httpbin.org/ip &>/dev/null
     sleep 2
   done

   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium fqdn cache list
   # Có thể thấy nhiều IPs được track (CDN load balancing)
   ```

3. Force refresh cache khi nghi ngờ stale:
   ```bash
   # Xem cache trước khi clean
   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium fqdn cache list

   # Force clean
   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium fqdn cache clean --matchpattern "httpbin.org"

   # Trigger re-resolve
   kubectl exec payment-service -- \
     curl -s --max-time 10 http://httpbin.org/ip

   # Verify fresh cache
   kubectl -n kube-system exec -it $CILIUM_POD \
     -- cilium fqdn cache list
   # httpbin.org → [fresh IPs]  ← Fresh resolve!

   # Cleanup observers
   pkill -f "port-forward" 2>/dev/null || true
   ```

4. Best practices để tránh Bug 2:
   ```
   Nguyên tắc:
   1. App không nên cache DNS lâu hơn DNS TTL
   2. Cilium tự refresh theo TTL từ DNS response
   3. Nếu dùng CDN: verify TTL ngắn (60-300s)
   4. Monitor với: hubble observe --verdict DROPPED
      → Nếu thấy random IPs bị drop = stale cache issue
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete ciliumnetworkpolicy payment-egress
kubectl delete pod payment-service
```

---

## ✅ Tổng kết

1. **Bug 1 — DNS thiếu:** toFQDNs KHÔNG hoạt động nếu không allow DNS port 53. Cilium cần intercept DNS response để biết IP của FQDN. Hubble show "DNS DROPPED" là dấu hiệu chắc chắn của Bug 1 — root cause ngay, không cần infer.
2. **Bug 2 — Stale cache:** CDN rotate IP → nếu app cache DNS lâu hơn Cilium TTL → app dùng IP cũ → Cilium BPF policy không có IP đó → intermittent DROP. `cilium fqdn cache list` cho thấy IPs đang được track hiện tại.
3. **toFQDNs template chuẩn:** Luôn có 2 phần — (1) DNS egress rule với `matchPattern` và (2) `toFQDNs` rule với `matchName`. Thiếu phần 1 → Bug 1. Thiếu align TTL → Bug 2.
4. **Debug order cho FQDN issues:** `hubble observe --verdict DROPPED` → nếu thấy DNS drop = Bug 1; nếu thấy HTTP/HTTPS drop với random IP = Bug 2 → kiểm tra `cilium fqdn cache list`.
