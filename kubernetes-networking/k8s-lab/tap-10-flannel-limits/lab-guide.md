# Lab Tập 10: Giới hạn Flannel — Lateral Movement & NetworkPolicy vô hiệu

Tập này chứng minh vấn đề nghiêm trọng nhất của Flannel trong production: **NetworkPolicy resource được K8s chấp nhận nhưng Flannel không enforce**. Bạn sẽ đóng vai attacker để thấy blast radius thực tế.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Flannel đang chạy (VXLAN hoặc host-gw đều được).
- `pod-a` đang chạy trên `worker1` (image `nicolaka/netshoot`).

---

## 🚀 Thí nghiệm 1: Setup các "mục tiêu" trong cluster

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Deploy pod giả lập database (lắng nghe TCP port 5432) và payment-api (nginx port 80):
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: database
     labels:
       app: database
   spec:
     nodeName: worker2
     containers:
     - name: db
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "5432"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: payment-api
     labels:
       app: payment
   spec:
     nodeName: worker2
     containers:
     - name: api
       image: nginx
       ports:
       - containerPort: 80
   EOF
   ```

2. Chờ các Pod sẵn sàng:
   ```bash
   kubectl wait --for=condition=Ready pod/database pod/payment-api --timeout=90s
   ```

3. Ghi lại IP của các targets:
   ```bash
   kubectl get pods -o wide
   DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')
   PAYMENT_IP=$(kubectl get pod payment-api -o jsonpath='{.status.podIP}')
   echo "Database IP: $DB_IP"
   echo "Payment API IP: $PAYMENT_IP"
   ```

---

## 💥 Thí nghiệm 2: Đóng vai attacker — Lateral Movement từ pod-a

Giả sử `pod-a` là frontend bị attacker chiếm quyền. Attacker có thể scan và kết nối đến mọi service khác.

**Thực hiện scan từ pod-a (trên Terminal `controlplane`):**

```bash
# Lấy IP targets
DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')
PAYMENT_IP=$(kubectl get pod payment-api -o jsonpath='{.status.podIP}')

kubectl exec pod-a -- bash -c "
  echo '=== Lateral Movement Demo ==='
  echo ''

  echo '[1] Scan Database (port 5432):'
  nc -zv $DB_IP 5432 2>&1 && echo 'Port 5432: OPEN - CÓ THỂ KẾT NỐI!'

  echo ''
  echo '[2] Curl Payment API (port 80):'
  curl -s -o /dev/null -w '%{http_code}' http://$PAYMENT_IP && echo ' ← HTTP response'

  echo ''
  echo '[3] Discover K8s API server:'
  nslookup kubernetes.default.svc.cluster.local 2>&1 | grep Address | tail -1

  echo ''
  echo '[4] Liệt kê tất cả services qua DNS:'
  nslookup nginx.default.svc.cluster.local 2>&1 | grep Address | tail -1
"
```

*Kết quả:* Tất cả đều thành công — Flannel không chặn gì cả.

---

## 🔬 Thí nghiệm 3: Apply NetworkPolicy — và chứng minh nó vô dụng

**Trên `controlplane`:**

1. Apply NetworkPolicy "deny all":
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: block-everything
   spec:
     podSelector: {}
     policyTypes:
     - Ingress
     - Egress
   EOF
   ```

2. Verify K8s chấp nhận resource:
   ```bash
   kubectl get networkpolicy
   # NAME               POD-SELECTOR   AGE
   # block-everything   <none> (All)   3s  ← K8s chấp nhận!
   ```

3. Thử lại scan từ pod-a — **mong đợi bị chặn nhưng thực tế:**
   ```bash
   DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')
   kubectl exec pod-a -- nc -zv $DB_IP 5432 2>&1
   # Connection to X.X.X.X 5432 port [tcp/postgresql] succeeded!
   # ← NetworkPolicy KHÔNG có tác dụng!
   ```

4. Chứng minh Flannel không cài bất kỳ iptables rule nào cho NetworkPolicy:
   ```bash
   multipass exec worker1 -- sudo iptables -L | grep -iE "network|policy|deny|block"
   # (không có output) ← Không có rule nào liên quan đến NetworkPolicy
   ```

   So sánh với Calico (chỉ để tham khảo — Calico sẽ có rules như):
   ```
   # Calico sẽ tạo ra:
   # ACCEPT  all  --  cali-tw-... (policy allow)
   # DROP    all  --  (default deny)
   ```

---

## 🔬 Thí nghiệm 4: Đo blast radius

**Tìm tất cả Pods đang chạy trong cluster:**

```bash
multipass shell controlplane
kubectl get pods -A -o wide | grep -v kube-system | grep -v kube-flannel
```

Thử kết nối từ pod-a đến tất cả Pod IPs:
```bash
# Lấy danh sách tất cả Pod IPs (không phải system pods)
ALL_IPS=$(kubectl get pods -o jsonpath='{.items[*].status.podIP}')

kubectl exec pod-a -- bash -c "
  for ip in $ALL_IPS; do
    result=\$(ping -c 1 -W 1 \$ip 2>/dev/null && echo 'REACHABLE' || echo 'TIMEOUT')
    echo \"\$ip: \$result\"
  done
"
```

*Kết quả:* Mọi Pod IP đều `REACHABLE` — blast radius = toàn bộ cluster.

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod database payment-api
kubectl delete networkpolicy block-everything
```

---

## ✅ Tổng kết

Bài lab chứng minh 3 điều:
1. **Flannel = zero security**: Bất kỳ Pod nào cũng reach được bất kỳ Pod nào — không phân biệt namespace, Node, hay label.
2. **NetworkPolicy với Flannel = false sense of security**: Resource được tạo, kubectl không báo lỗi, nhưng không có gì được enforce. Đây là **nguy hiểm lớn hơn** so với việc biết mình không có security.
3. **Blast radius = toàn cluster**: 1 Pod bị chiếm → attacker có thể reach toàn bộ workload.

**Giải pháp:** Tập 11 sẽ chuyển sang Calico — CNI enforce NetworkPolicy thật sự thông qua iptables hooks trên mỗi Node.
