# Lab 1.1: Inspect Network Namespace của Pod từ Worker Node

## 🎯 Mục tiêu
- Xác nhận `pause` container đang tồn tại trên Node.
- Tìm `veth pair` kết nối Pod vào Node.
- Chui vào Network Namespace của Pod từ OS của Node.

## ✅ Yêu cầu tiên quyết
- Cluster 3 nodes đang chạy (CNI đã cài).
- SSH được vào Worker Node.
- Đã cài `netshoot` hoặc có `nsenter` trên Node.

---

## 🔬 Bước 1: Tạo Pod thử nghiệm

```bash
kubectl run nginx-test --image=nginx --restart=Never
kubectl get pod nginx-test -o wide
# Ghi lại NODE và POD IP
```

---

## 🔬 Bước 2: SSH vào Worker Node chứa Pod

```bash
# Vagrant
vagrant ssh worker1

# Multipass
multipass shell worker1
```

---

## 🔬 Bước 3: Tìm Pause Container bằng crictl

```bash
# Liệt kê tất cả container đang chạy trên Node
sudo crictl ps

# Bạn sẽ thấy: nginx-test và một container "pause" đi kèm
# Tìm Container ID của pause container

# Lấy thông tin network của Pod
sudo crictl inspect <CONTAINER_ID_CUA_NGINX> | grep -i pid
```

---

## 🔬 Bước 4: Xem veth pair từ phía Node

```bash
# Liệt kê tất cả network interfaces trên Node
ip link show

# Chú ý các interface dạng vethXXXXXX
# Đối chiếu với Pod IP để biết đây là veth của Pod nào
ip addr show | grep -A2 veth
```

---

## 🔬 Bước 5: Chui vào Network Namespace của Pod

```bash
# Lấy PID của process trong Pod
POD_PID=$(sudo crictl inspect <CONTAINER_ID_CUA_NGINX> | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['pid'])")

echo "Pod PID: $POD_PID"

# Dùng nsenter để vào network namespace của Pod
sudo nsenter -t $POD_PID -n ip addr show
# → Bạn sẽ thấy eth0 với IP của Pod, đang đứng từ HOST OS!

sudo nsenter -t $POD_PID -n ip route show
# → Bạn sẽ thấy default route và route table của Pod
```

---

## 🔬 Bước 6: Bắt gói tin từ phía Node trên veth pair

```bash
# Tìm tên veth pair của Pod
VETH=$(ip link show | grep -B1 "master cni0" | grep veth | awk '{print $2}' | tr -d ':')

# Bắt gói tin trực tiếp trên veth pair của Pod
sudo tcpdump -i $VETH -nn
```

Từ terminal khác, gửi traffic vào Pod:
```bash
kubectl exec -it nginx-test -- curl localhost
```

---

## ✅ Câu hỏi kiểm tra

1. Container `pause` giữ vai trò gì? Nó có đang chạy process nào không?
2. IP của Pod trong `nsenter` có khớp với `kubectl get pod -o wide` không?
3. Tên veth trên Node được đặt tên theo quy tắc gì?

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod nginx-test
```
