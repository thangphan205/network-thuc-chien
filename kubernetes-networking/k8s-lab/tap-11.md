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

# Tập 11
## Lateral Movement & Blast Radius: Bài toán bảo mật Flannel bỏ qua

**Phần 2 — Calico** · `#security` `#lateral-movement` `#blast-radius` `#calico`

---

## Mục tiêu tập này

- Hiểu kỹ thuật lateral movement trong K8s environment
- Tính toán blast radius với công thức cụ thể
- Migrate cluster từ Flannel sang Calico
- Verify NetworkPolicy bây giờ được enforce thực sự

**Prerequisites:** Cluster từ Tập 10 với Flannel (chuẩn bị migrate sang Calico)

---

## Lateral Movement: Từ 1 Pod → Toàn cluster

```
Kịch bản thực tế (đã xảy ra nhiều lần):

Bước 1: Frontend Pod có Log4Shell vulnerability
         → Attacker chạy code từ xa trong frontend

Bước 2: Từ frontend, attacker chạy:
         nmap 10.244.0.0/16 -p 3306,5432,6379,27017,8080,9200
         → Tìm thấy: database (3306), redis (6379), elasticsearch (9200)

Bước 3: Tấn công Database
         mysql -h 10.244.2.10 -u root -p''  (try default passwords)
         → Nếu thành công: dump toàn bộ user data

Bước 4: Pivoting — từ Database sang service khác
         Dùng credentials trong DB để tấn công payment service
         Inject malicious data

Tổng thiệt hại: Toàn bộ cluster, mọi service, mọi data
```

---

## Blast Radius: Đo lường định lượng

```
Blast Radius = Số lượng service có thể bị tấn công
               ────────────────────────────────────
               từ 1 Pod bị compromise

Flannel (không policy):
  Blast Radius = N-1  (N = tổng số services)
  50 services → Blast Radius = 49  (gần 100%)

Calico + Default Deny + Least Privilege:
  Frontend policy: chỉ gọi được backend:8080 và DNS:53
  Blast Radius = 2  (chỉ backend và DNS)
```

**Nguyên tắc Least Privilege trong K8s:**
```
Mỗi Pod chỉ có quyền giao tiếp với ĐÚNG service nó cần
Không hơn, không kém — Default Deny cho phần còn lại
```

---

<!-- _class: lab -->

## Lab: Migrate từ Flannel sang Calico

```bash
multipass shell k8s-master

# Bước 1: Xóa Flannel
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Xóa network interfaces và configs trên mọi Node
for NODE in k8s-worker1 k8s-worker2; do
  multipass exec $NODE -- bash -c '
    sudo ip link del cni0 2>/dev/null || true
    sudo ip link del flannel.1 2>/dev/null || true
    sudo rm -rf /etc/cni/net.d/*
    sudo rm -rf /run/flannel/
  '
done

# Trên master cũng cleanup
sudo ip link del cni0 2>/dev/null || true
sudo ip link del flannel.1 2>/dev/null || true
sudo rm -rf /etc/cni/net.d/*

# Nodes sẽ về NotReady (không có CNI)
kubectl get nodes
# NAME          STATUS     ROLES
# k8s-master    NotReady   control-plane
```

---

## Lab: Cài Calico via Tigera Operator

```bash
# Cài Tigera Operator (quản lý lifecycle của Calico)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml

# Cài Calico installation CR
kubectl create -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet   # VXLAN khi cross-subnet, routing khi cùng subnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# Theo dõi quá trình cài đặt
watch kubectl get pods -n calico-system
# Sau 2-3 phút: tất cả Pods Running

kubectl get nodes
# NAME          STATUS   ROLES
# k8s-master    Ready    control-plane   ← Calico đang chạy!
# k8s-worker1   Ready    <none>
# k8s-worker2   Ready    <none>
```

---

## Lab: Verify NetworkPolicy được enforce

```bash
# Deploy lại services từ Tập 10
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: database
  labels: {app: database}
spec:
  containers:
  - name: db
    image: nicolaka/netshoot
    command: ["nc", "-lk", "-p", "5432"]
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels: {app: frontend}
spec:
  containers:
  - name: app
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

kubectl wait --for=condition=Ready pod/database pod/frontend --timeout=60s

DB_IP=$(kubectl get pod database -o jsonpath='{.status.podIP}')

# Trước khi có NetworkPolicy: vẫn kết nối được
kubectl exec frontend -- nc -zv $DB_IP 5432   # OK

# Apply Default Deny
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF

# Bây giờ: BỊ CHẶN (Calico enforce!)
kubectl exec frontend -- nc -zv $DB_IP 5432   # Timeout ← CALICO CHẶN!
```

---

## So sánh trước/sau migrate

| | Flannel | Calico |
| :--- | :--- | :--- |
| NetworkPolicy | Bị bỏ qua | **Được enforce** |
| Blast Radius (1 Pod compromised) | **Toàn cluster** | Chỉ services được allow |
| Default posture | Allow all | **Deny all (sau khi apply policy)** |
| iptables rules | Chỉ kube-proxy | **kube-proxy + Calico Felix** |

**Sau khi migrate sang Calico:**
```bash
# Kiểm tra Calico đang enforce iptables
sudo iptables -L | grep cali
# Chain cali-FORWARD (policy DROP)
# Chain cali-from-wl-dispatch
# Chain cali-to-wl-dispatch
# → Felix đã install rules!
```

> **Tập tiếp theo:** Giải phẫu kiến trúc Calico — Felix, BIRD, Datastore làm gì?
