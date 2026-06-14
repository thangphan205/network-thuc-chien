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

   # DNS cũng bị block (vì DNS resolve qua world):
   kubectl exec api-client -- nslookup httpbin.org
   # ;; connection timed out  ← DNS cũng bị block
   ```

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
   # curl: (28) Connection timed out  ✅ example.com blocked!
   ```

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
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium bpf policy list | grep -A2 "api-client"
   # Thấy CIDR entries tương ứng với IPs đã resolve
   ```

3. Quan sát DNS proxy events qua Hubble:
   ```bash
   kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
   sleep 2

   # Watch DNS flows
   hubble observe --pod api-client \
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
   ```bash
   # Test: subdomain của httpbin.org (nếu matchPattern: "*.httpbin.org")
   # Note: httpbin.org không có subdomain thực, nhưng pattern sẽ match
   # Để demo: thêm google.com với wildcard
   kubectl patch ciliumnetworkpolicies api-client-fqdn-policy \
     --type merge --patch '
   {
     "spec": {
       "egress": [
         {
           "toFQDNs": [
             {"matchName": "httpbin.org"},
             {"matchPattern": "*.httpbin.org"}
           ]
         }
       ]
     }
   }' 2>/dev/null || echo "Note: patch syntax varies — manual edit if needed"
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
