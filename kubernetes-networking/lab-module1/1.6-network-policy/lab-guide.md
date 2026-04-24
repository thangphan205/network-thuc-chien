# Lab 1.6: NetworkPolicy — Default-deny, Fix DNS & Thử nghiệm CNI

## 🎯 Mục tiêu
- Áp dụng `default-deny` và quan sát ứng dụng bị break.
- Viết NetworkPolicy đúng chuẩn, bao gồm cả rule cho DNS.
- Kiểm chứng rằng Flannel không thực thi NetworkPolicy.

---

## 🔬 Bước 1: Tạo môi trường thử nghiệm

```bash
# Tạo 2 namespace
kubectl create namespace frontend
kubectl create namespace backend

# Tạo Pod backend (database giả)
kubectl run db --image=nginx -n backend --labels="app=db"
kubectl expose pod db -n backend --port=80 --name=db-svc

# Tạo Pod frontend (client)
kubectl run client --image=nicolaka/netshoot -n frontend \
  --labels="role=frontend" -- sleep infinity

# Kiểm tra kết nối ban đầu (phải thông)
kubectl exec -n frontend client -- curl -s db-svc.backend.svc.cluster.local
# → Thấy nginx page = THÔNG
```

---

## 🔬 Bước 2: Apply Default-deny cho namespace backend

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
EOF

# Thử lại kết nối — phải bị chặn
kubectl exec -n frontend client -- curl -s --max-time 3 db-svc.backend.svc.cluster.local
# → timeout!
```

---

## 🔬 Bước 3: Viết Policy sai (Lỗi kinh điển — quên DNS)

```bash
# Policy sai: chỉ mở port 80, quên không mở DNS (port 53)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-wrong
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: frontend
      ports:
        - port: 80
EOF

# Thử kết nối bằng DNS name — vẫn lỗi!
kubectl exec -n frontend client -- curl -s --max-time 3 db-svc.backend.svc.cluster.local
# timeout! (DNS query bị chặn bởi Egress deny của frontend)

# Thử bằng IP trực tiếp — có thể thông hoặc không tùy config
DB_IP=$(kubectl get pod db -n backend -o jsonpath='{.status.podIP}')
kubectl exec -n frontend client -- curl -s --max-time 3 $DB_IP
```

---

## 🔬 Bước 4: Viết Policy đúng chuẩn (có DNS rule)

```bash
# Xóa policy sai
kubectl delete networkpolicy -n frontend --all

# Tạo policy đúng cho frontend: cho phép DNS + kết nối đến backend
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: frontend
spec:
  podSelector:
    matchLabels:
      role: frontend
  policyTypes:
    - Egress
  egress:
    - ports:          # ← QUAN TRỌNG: Luôn mở DNS!
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: backend
      ports:
        - port: 80
EOF

# Thử lại — phải thông
kubectl exec -n frontend client -- curl -s db-svc.backend.svc.cluster.local
# → Thấy nginx page = THÀNH CÔNG!
```

---

## 🔬 Bước 5: Kiểm chứng CNI nào thực thi NetworkPolicy

```bash
# Xem CNI plugin đang được cài trên Node
ls /etc/cni/net.d/
# Nếu thấy 10-flannel.conflist → Flannel không thực thi Policy!

# Kiểm tra: Apply policy nhưng vẫn thông traffic
# Nếu dùng Flannel: Policy không có tác dụng
# Nếu dùng Calico/Cilium: Policy được thực thi

# Xem iptables rules do Calico sinh ra (nếu dùng Calico):
sudo iptables -L | grep cali
```

---

## ✅ Câu hỏi kiểm tra

1. Tại sao policy `Egress` lại cần thiết để "cho phép gửi request đến service khác"?
2. CoreDNS nằm ở namespace `kube-system`. Làm sao viết policy chính xác để cho phép DNS query đến đúng CoreDNS?
3. Nếu bạn dùng Flannel mà apply NetworkPolicy, điều gì xảy ra? Tại sao?

---

## 🧹 Dọn dẹp

```bash
kubectl delete namespace frontend backend
```
