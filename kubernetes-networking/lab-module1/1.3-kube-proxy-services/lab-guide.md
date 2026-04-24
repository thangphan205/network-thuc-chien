# Lab 1.3: Phân tích Kube-proxy iptables, IPVS & nftables

## 🎯 Mục tiêu
- Tạo Service và phân tích chain iptables được sinh ra tự động.
- Chuyển kube-proxy sang IPVS mode và kiểm tra bảng IPVS.
- Thử nghiệm `externalTrafficPolicy: Local`.

---

## 🔬 Bước 1: Tạo Deployment + Service ClusterIP

```bash
# Tạo deployment với 3 replicas
kubectl create deployment web --image=nginx --replicas=3

# Tạo ClusterIP Service
kubectl expose deployment web --port=80 --name=web-svc

# Lấy ClusterIP
kubectl get svc web-svc
# NAME      TYPE        CLUSTER-IP     PORT(S)
# web-svc   ClusterIP   10.96.XX.XX    80/TCP
```

---

## 🔬 Bước 2: Phân tích iptables chains trên Node

```bash
# SSH vào Worker Node
vagrant ssh worker1

# Xem tất cả chain liên quan đến Service
sudo iptables-save | grep "web-svc\|KUBE-SVC\|KUBE-SEP"

# Xem chain KUBE-SERVICES (điểm vào)
sudo iptables -t nat -L KUBE-SERVICES -n --line-numbers

# Tìm chain KUBE-SVC của web-svc và xem load balancing
sudo iptables -t nat -L <TÊN_CHAIN_KUBE-SVC> -n -v
# Chú ý: module statistic với --probability để phân tải ngẫu nhiên
```

---

## 🔬 Bước 3: Chuyển sang IPVS mode

```bash
# Trên Control Plane, chỉnh kube-proxy ConfigMap
kubectl edit configmap kube-proxy -n kube-system
# Tìm dòng: mode: ""
# Sửa thành: mode: "ipvs"

# Restart kube-proxy DaemonSet
kubectl rollout restart daemonset kube-proxy -n kube-system
kubectl rollout status daemonset kube-proxy -n kube-system
```

---

## 🔬 Bước 4: Kiểm tra bảng IPVS

```bash
# SSH vào Worker Node
vagrant ssh worker1

# Cài ipvsadm nếu chưa có
sudo apt install -y ipvsadm

# Xem bảng IPVS
sudo ipvsadm -Ln
# TCP  10.96.XX.XX:80 rr
#   -> 10.244.1.X:80   Round-Robin
#   -> 10.244.1.X:80   Round-Robin
#   -> 10.244.2.X:80   Round-Robin

# Xem số lần kết nối đến từng Pod
sudo ipvsadm -Ln --stats
```

---

## 🔬 Bước 5: Thử nghiệm externalTrafficPolicy

```bash
# Tạo NodePort Service với policy mặc định (Cluster)
kubectl expose deployment web --port=80 --type=NodePort --name=web-nodeport

# Kiểm tra Node IP và NodePort
kubectl get svc web-nodeport

# Từ máy host, curl đến NodePort
curl http://192.168.56.11:<NODEPORT>

# Xem source IP trong log Nginx
kubectl logs -l app=web | grep "GET /"
# Source IP là Node IP, không phải IP máy bạn!

# Thử đổi sang Local policy
kubectl patch svc web-nodeport -p '{"spec":{"externalTrafficPolicy":"Local"}}'

# Curl lại và xem log — Source IP giờ là IP máy bạn
```

---

## ✅ Câu hỏi kiểm tra

1. Trong iptables mode, rule `--probability` được tính toán như thế nào cho 3 pods? (Gợi ý: 1/3, 1/2, 1/1)
2. Tại sao IPVS dùng hash table trong khi iptables dùng danh sách tuần tự?
3. Khi dùng `externalTrafficPolicy: Local`, điều gì xảy ra nếu Node không có Pod nào?

---

## 🧹 Dọn dẹp

```bash
kubectl delete deployment web
kubectl delete svc web-svc web-nodeport
```
