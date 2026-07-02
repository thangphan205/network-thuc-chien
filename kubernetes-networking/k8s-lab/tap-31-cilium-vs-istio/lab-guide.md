# Lab Tập 31: Cilium + Istio — Khi nào kết hợp, khi nào dùng Cilium thuần

Tập này phân tích decision matrix, verify Cilium và Istio không conflict, và đo overhead của Istio sidecar so với Cilium-only.

## 🛠 Yêu cầu chuẩn bị
- Cilium đang chạy (từ Tập 23).
- Ít nhất 6GB RAM cluster (Istio cần ~2GB thêm).
- Internet access để pull Istio installer.
- **metrics-server đã cài** (`kubectl top` cần API `metrics.k8s.io` — không có sẵn trong cluster nếu chưa cài, mọi lệnh `kubectl top` bên dưới sẽ báo lỗi `error: Metrics API not available`):
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  # Nếu cluster dùng self-signed kubelet cert (thường gặp với kubeadm), thêm flag:
  kubectl -n kube-system patch deployment metrics-server --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  kubectl -n kube-system wait --for=condition=Available deployment/metrics-server --timeout=90s
  ```

> **Lưu ý:** Istio install là optional nếu lab thiếu RAM. Phần 1-2 có thể thực hành mà không cần cài Istio.

---

## 🔬 Thực nghiệm 1: Baseline — Cilium standalone status

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Verify Cilium đang healthy:
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)

   kubectl -n kube-system exec -it $CILIUM_POD -- cilium status
   # Cilium:                Ok      1.19.5 (v1.19.5-xxxxxxx)
   # KubeProxyReplacement:  True    [eth0 (Direct Routing)]
   ```
   > **💡 Lưu ý version (đã kiểm chứng trên Cilium v1.19.5):** không có field `BPF:` hay `Sockops:` đứng riêng trong `cilium status` (không tồn tại trong formatter thật). Muốn xem chi tiết Socket LB (thay cho `Sockops` cũ, bị loại bỏ từ v1.14):
   ```bash
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium status --verbose | grep -A1 "Socket LB"
   # Socket LB:            Enabled
   # Socket LB Coverage:   Full
   ```

2. Kiểm tra RAM usage của pod không có sidecar:
   ```bash
   kubectl run no-sidecar --image=nicolaka/netshoot -- sleep infinity
   kubectl wait --for=condition=Ready pod/no-sidecar --timeout=60s

   kubectl top pod no-sidecar
   # NAME         CPU(cores)   MEMORY(bytes)
   # no-sidecar   1m           8Mi  ← Rất nhỏ

   kubectl get pod no-sidecar -o json | \
     jq '.spec.containers | length'
   # 1  ← Chỉ 1 container (no sidecar)
   ```

3. Ghi nhận Cilium endpoint cho pod này:
   ```bash
   POD_IP=$(kubectl get pod no-sidecar -o jsonpath='{.status.podIP}')
   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list | grep $POD_IP
   # Cilium quản lý endpoint
   ```

---

## 🔬 Thực nghiệm 2: Cài Istio (optional — cần RAM)

**Trên `controlplane`:**

> Skip thực nghiệm này nếu cluster < 6GB RAM. Xem kết quả expected bên dưới.

1. Download và cài Istio:
   > **💡 Lưu ý:** Bản dưới đây minh hoạ Istio sidecar mode cổ điển (nơi phát sinh overhead per-pod đang so sánh trong lab). Từ Istio 1.24 (GA), **Ambient Mode** dùng 1 proxy `ztunnel` dùng chung mỗi node thay vì sidecar per-pod, giảm phần lớn overhead RAM này — luận điểm "+50-70MB/pod" ở Tổng kết chỉ đúng với sidecar mode, không áp dụng cho ambient mode. Cân nhắc dùng version Istio mới hơn nếu muốn so sánh cả 2 mode.
   ```bash
   curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
   cd istio-1.20.0/
   export PATH=$PWD/bin:$PATH

   # Cài minimal profile (ít RAM nhất)
   istioctl install --set profile=minimal -y
   # ✅ Istio core installed
   ```

2. Verify Istio running:
   ```bash
   kubectl -n istio-system get pods
   # istiod-xxxxx  1/1  Running  ← Istiod (control plane)

   # Cilium vẫn running sau Istio install?
   kubectl -n kube-system get pods -l k8s-app=cilium
   # All 3 pods: Running ✅ — không conflict!
   ```

3. Verify Cilium vẫn manage networking (không bị Istio override):
   ```bash
   CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
     -o name | head -1)
   kubectl -n kube-system exec -it $CILIUM_POD -- cilium status
   # Cilium: OK ✅ — vẫn hoạt động bình thường
   ```

---

## 💥 Thực nghiệm 3: So sánh overhead — với và không có sidecar

**Trên `controlplane`:**

1. Nếu đã cài Istio — deploy pod với sidecar injection:
   ```bash
   kubectl create namespace demo-mesh 2>/dev/null || true
   kubectl label namespace demo-mesh istio-injection=enabled

   kubectl apply -n demo-mesh -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: with-sidecar
     labels:
       app: demo
   spec:
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF

   kubectl -n demo-mesh wait --for=condition=Ready \
     pod/with-sidecar --timeout=90s
   ```

2. So sánh containers và RAM:
   ```bash
   # Không có sidecar:
   kubectl get pod no-sidecar -o json | \
     jq '.spec.containers | length'
   # 1

   # Với Istio sidecar:
   kubectl -n demo-mesh get pod with-sidecar -o json | \
     jq '.spec.containers | map(.name)'
   # ["app", "istio-proxy"]  ← 2 containers!

   kubectl top pods --all-namespaces | grep -E "no-sidecar|with-sidecar"
   # no-sidecar    1m    8Mi   ← Không sidecar
   # with-sidecar  3m    72Mi  ← +64MB cho istio-proxy!
   ```

3. Xem Cilium CŨNG manage pod có sidecar:
   ```bash
   SIDECAR_IP=$(kubectl -n demo-mesh get pod with-sidecar \
     -o jsonpath='{.status.podIP}')

   kubectl -n kube-system exec -it $CILIUM_POD -- \
     cilium endpoint list | grep $SIDECAR_IP
   # Pod với sidecar vẫn có endpoint trong Cilium ✅
   # → Cilium handle L3/L4, Istio handle L7 application layer
   ```

---

## 🔬 Thực nghiệm 4: Decision matrix — hands-on evaluation

**Trên `controlplane`:**

1. Test Cilium L7 policy trên pod với sidecar (cả hai layers):
   ```bash
   # Nếu đang dùng cả Cilium + Istio:
   # Cilium policy được eval TRƯỚC Istio sidecar
   # → Packet bị drop bởi Cilium → không bao giờ đến Envoy của Istio

   # Test: NetworkPolicy (Cilium layer) vẫn hoạt động với Istio pod
   kubectl apply -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: deny-to-sidecar-pod
     namespace: demo-mesh
   spec:
     podSelector:
       matchLabels:
         app: demo
     policyTypes:
     - Ingress
     ingress: []
   EOF

   # Thử connect vào pod có sidecar:
   kubectl exec no-sidecar -- \
     nc -zv -w 3 $SIDECAR_IP 8080 &>/dev/null || echo "Blocked by Cilium"
   # Blocked by Cilium ✅ — Cilium layer hoạt động dù có Istio
   ```

2. Dọn test policy:
   ```bash
   kubectl -n demo-mesh delete networkpolicy deny-to-sidecar-pod
   ```

3. Tổng kết decision points:
   ```bash
   echo "=== Decision Matrix Summary ==="
   echo "Cilium only: NetworkPolicy + L7 basic + Hubble observability"
   echo "Overhead: ~0MB extra per pod"
   echo ""
   echo "Cilium + Istio: Full service mesh features"
   echo "Overhead: +50-70MB per pod (istio-proxy sidecar)"
   echo ""
   echo "Rule: Start Cilium only. Add Istio when you NEED:"
   echo "  - Traffic splitting (canary/blue-green)"
   echo "  - Automatic mTLS service-to-service"
   echo "  - Circuit breaker at application level"
   ```

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod no-sidecar
kubectl delete namespace demo-mesh 2>/dev/null || true

# Nếu muốn uninstall Istio:
# istioctl uninstall --purge -y
# kubectl delete namespace istio-system
```

---

## ✅ Tổng kết

1. **Cilium và Istio không conflict:** Cilium handle L3/L4 network layer (CNI), Istio handle L7 application mesh layer (sidecar). Cả hai cùng tồn tại — Cilium evaluate policy trước khi packet đến Istio sidecar.
2. **Overhead thực của Istio:** Mỗi pod với sidecar tốn thêm +50-70MB RAM cho `istio-proxy`. Cluster 100 pods = +5-7GB RAM overhead. Không trivial!
3. **Cilium Service Mesh:** Traffic management sidecar-less (Ingress/Gateway API) đã mature từ Cilium ~1.12-1.13 — 80% use cases không cần Istio. Riêng **mTLS** (mutual auth) mới ở giai đoạn Beta từ **1.14** (không phải 1.12), và theo upgrade guide chính thức, `mesh-auth-enabled` **tắt mặc định từ v1.19** (đang chờ feedback cộng đồng, tích hợp với ztunnel đang phát triển) — chưa nên xem là giải pháp mTLS "đã settled" để thay Istio ngay.
4. **Decision rule:** Bắt đầu Cilium only. Thêm Istio khi cụ thể cần: canary deployment, automatic mTLS, circuit breaker, hay distributed tracing (Jaeger). Đừng add Istio "phòng khi cần" — overhead có thật.
