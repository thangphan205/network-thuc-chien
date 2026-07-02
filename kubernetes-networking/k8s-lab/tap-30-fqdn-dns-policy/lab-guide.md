# Lab Tập 30: DNS Policy với toFQDNs — Filter egress theo domain

Tập này deploy pod với egress policy cho phép chỉ một số domain, verify Cilium DNS proxy track IPs tự động, và quan sát CDN multi-IP được handle đúng.

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy (từ Tập 23).
- Cluster nodes có internet access (cần resolve và connect httpbin.org).

---

## 🔬 Thực nghiệm 1: Verify internet access trước khi có policy

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Deploy api-client pod:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: api-client
     labels:
       app: api-client
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF

   kubectl wait --for=condition=Ready pod/api-client --timeout=60s
   ```

2. Verify có thể reach internet:
   ```bash
   kubectl exec api-client -- curl -s --max-time 5 http://httpbin.org/ip
   # {"origin": "x.x.x.x"}  ← Internet accessible

   kubectl exec api-client -- curl -s --max-time 5 http://example.com | head -3
   # <!doctype html>...  ← Also accessible
   ```

---

## 💥 Thực nghiệm 2: Apply default deny egress + verify blocked

**Trên `controlplane`:**

1. Apply default deny egress (Cilium):
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: api-client-default-deny
   spec:
     endpointSelector:
       matchLabels:
         app: api-client
     egressDeny:
     - toEntities:
       - "world"
   EOF
   ```

2. Verify không reach được internet:
   ```bash
   kubectl exec api-client -- curl -s --max-time 5 http://httpbin.org/ip
   # curl: (28) Connection timed out  ← Blocked!

   # DNS cũng bị block:
   kubectl exec api-client -- nslookup httpbin.org
   # ;; connection timed out  ← DNS cũng bị block
   ```
   > **💡 Lý do DNS cũng bị block:** KHÔNG phải vì "DNS đi qua entity world" (kube-dns là Service/Pod trong cluster, không bao giờ mang identity `world`). Lý do thật: policy này có `egressDeny` (dù chỉ chọn `world`) nên endpoint tự động chuyển sang chế độ **default-deny-egress toàn bộ** — không có bất kỳ allow rule nào (kể cả cho kube-dns) nên mọi egress traffic, kể cả DNS, đều bị chặn.

---

## 🔬 Thực nghiệm 3: Apply toFQDNs policy — allow httpbin.org only

**Trên `controlplane`:**

1. Delete default deny và apply toFQDNs policy đầy đủ:
   ```bash
   kubectl delete ciliumnetworkpolicies api-client-default-deny

   kubectl apply -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: api-client-fqdn-policy
   spec:
     endpointSelector:
       matchLabels:
         app: api-client
     egress:
     # Bước 1: Allow DNS resolve cho domains được phép
     - toEndpoints:
       - matchLabels:
           k8s-app: kube-dns
           k8s:io.kubernetes.pod.namespace: kube-system
       toPorts:
       - ports:
         - port: "53"
           protocol: UDP
         - port: "53"
           protocol: TCP
         rules:
           dns:
           - matchPattern: "httpbin.org"
           - matchPattern: "*.httpbin.org"

     # Bước 2: Allow egress đến httpbin.org IPs (Cilium auto-resolve)
     - toFQDNs:
       - matchName: "httpbin.org"
       toPorts:
       - ports:
         - port: "80"
           protocol: TCP
         - port: "443"
           protocol: TCP
   EOF
   ```

2. Test allowed domain:
   ```bash
   kubectl exec api-client -- curl -s --max-time 10 http://httpbin.org/ip
   # {"origin": "x.x.x.x"}  ✅ httpbin.org accessible!
   ```

3. Test blocked domain:
   ```bash
   kubectl exec api-client -- curl -s --max-time 5 http://example.com
   # curl: (6) Could not resolve host: example.com  ✅ example.com blocked!
   ```
   > **💡 Vì sao lỗi (6) chứ không phải timeout:** `example.com` không nằm trong allow-list DNS (`rules.dns` chỉ cho `httpbin.org`/`*.httpbin.org`) nên Cilium DNS proxy trả **REFUSED** ngay ở bước resolve (mặc định `--tofqdns-dns-reject-response-code=refused`) — request bị chặn trước cả khi có IP để kết nối, nên curl báo lỗi resolve (exit code 6), không phải timeout kết nối TCP (exit code 28).

4. Verify Cilium đã track IPs từ DNS:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium fqdn cache list
   # httpbin.org → [34.239.x.x, 54.175.x.x, 18.232.x.x]  TTL: 30s
   # ← Nhiều IPs! CDN multi-IP được handle tự động
   ```

---

## 🔬 Thực nghiệm 4: Demo CDN IP rotation handling

**Trên `controlplane`:**

1. Xem số IPs được track cho httpbin.org:
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium fqdn cache list | grep httpbin
   # httpbin.org → [54.x.x.x, 34.x.x.x, 18.x.x.x, ...]
   # ← Có thể 3-10 IPs tùy CDN rotation
   ```

2. Verify BPF policy map có các IPs này:
   ```bash
   # cilium bpf policy list chỉ hiện ID số, không có tên pod literal "api-client"
   # → lấy endpoint ID của api-client trước
   ENDPOINT_ID=$(kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list | grep api-client | awk '{print $1}')

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf policy get $ENDPOINT_ID
   # Thấy rule Allow với PREFIX ứng với các IP đã resolve (CIDR /32 per IP)

   # Muốn xem trực tiếp IP ↔ identity mapping:
   kubectl -n kube-system exec -it $CILIUM_POD -- cilium ipcache list | grep -A1 -B1 "fqdn"
   ```

3. Quan sát DNS proxy events qua Hubble:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2

   # Watch DNS flows
   hubble observe --server localhost:4245 --pod api-client \
     --protocol dns --follow &
   HUBBLE_PID=$!

   # Trigger DNS resolve
   kubectl exec api-client -- curl -s http://httpbin.org/ip &>/dev/null
   kubectl exec api-client -- curl -s http://example.com &>/dev/null || true

   sleep 3
   kill $HUBBLE_PID 2>/dev/null

   # Hubble output:
   # api-client → kube-dns  DNS Request: httpbin.org  FORWARDED
   # api-client → kube-dns  DNS Request: example.com  FORWARDED
   # (DNS cho phép resolve — blocked ở TCP connect sau đó)
   ```

4. Verify matchPattern wildcard — add subdomain allow:

   > **⚠️ Lưu ý quan trọng:** `spec.egress` của CiliumNetworkPolicy là 1 array thường (không có merge-key) — `kubectl patch --type merge` sẽ **thay thế toàn bộ mảng `egress`**, không phải "thêm vào". Nếu chỉ patch mỗi `toFQDNs`, rule DNS-allow (`toEndpoints: kube-dns`) đã tạo ở Bước 1 (Thực nghiệm 3) sẽ **bị xoá mất**, kéo theo DNS bắt đầu bị REFUSED hoàn toàn — hỏng luôn kịch bản đang test. Cách đúng là áp lại **toàn bộ YAML gốc** kèm thêm entry mới, không dùng partial merge patch:
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: api-client-fqdn-policy
   spec:
     endpointSelector:
       matchLabels:
         app: api-client
     egress:
     - toEndpoints:
       - matchLabels:
           k8s-app: kube-dns
           k8s:io.kubernetes.pod.namespace: kube-system
       toPorts:
       - ports:
         - port: "53"
           protocol: UDP
         - port: "53"
           protocol: TCP
         rules:
           dns:
           - matchPattern: "httpbin.org"
           - matchPattern: "*.httpbin.org"
     - toFQDNs:
       - matchName: "httpbin.org"
       - matchPattern: "*.httpbin.org"
       toPorts:
       - ports:
         - port: "80"
           protocol: TCP
         - port: "443"
           protocol: TCP
   EOF
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete ciliumnetworkpolicies api-client-fqdn-policy 2>/dev/null || true
kubectl delete pod api-client
pkill -f "port-forward" 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **CDN multi-IP trap với CIDR:** CDN như Stripe/AWS có 50-200 IPs thay đổi theo DNS TTL → whitelist 1 IP đủ để fail production. toFQDNs giải quyết bằng cách track tất cả IPs tự động.
2. **Cilium DNS proxy transparent:** BPF intercept UDP:53 → Cilium proxy → kube-dns → capture IPs → update BPF policy map → forward response. Pod không biết proxy đang intercept.
3. **Phải allow DNS trước khi allow FQDN:** Không có DNS allow → Pod không resolve được domain → connection fail ngay cả khi toFQDNs đúng. DNS allow cần `rules.dns.matchPattern` riêng.
4. **matchName vs matchPattern:** `matchName` = exact (api.stripe.com), `matchPattern` = glob wildcard (*.stripe.com). Để cover cả root domain và subdomains phải dùng cả hai.
