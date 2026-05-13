#!/bin/bash

# Script tự động kiểm tra bài lab Services & Kube-proxy (Tập 3)
# Yêu cầu: Chạy trên máy host (macOS/Linux) đã cài Multipass. Cụm K8s đã Ready.

echo "=================================================="
echo "🧪 BẮT ĐẦU KIỂM TRA: SERVICES & KUBE-PROXY IPTABLES"
echo "=================================================="

run_cp() { multipass exec controlplane -- "$@"; }
run_w1() { multipass exec worker1 -- "$@"; }

echo -e "\n[1/4] 📦 KHỞI TẠO NGINX DEPLOYMENT VÀ SERVICE..."
run_cp kubectl create deployment nginx --image=nginx --replicas=3 >/dev/null 2>&1
run_cp kubectl expose deployment nginx --port=80 --type=ClusterIP >/dev/null 2>&1

echo "⏳ Đang chờ các Pod Nginx khởi chạy..."
run_cp kubectl rollout status deployment/nginx --timeout=60s >/dev/null 2>&1

CLUSTER_IP=$(run_cp kubectl get svc nginx -o jsonpath='{.spec.clusterIP}')
echo "-> ClusterIP của Nginx Service: $CLUSTER_IP"

echo -e "\n[2/4] 🏓 SO SÁNH PING VÀ CURL VÀO CLUSTER IP..."
echo "Thử lệnh PING (Dự kiến: Sẽ thất bại / Timeout do ICMP không có port):"
run_cp ping -c 1 -W 1 $CLUSTER_IP || echo "-> PING thất bại đúng như dự đoán!"

echo "Thử lệnh CURL (Dự kiến: Sẽ thành công do iptables bắt đúng port TCP 80):"
run_cp curl -s --max-time 2 http://$CLUSTER_IP | grep -o "Welcome to nginx!" || echo "Curl thất bại!"

echo -e "\n[3/4] 🔍 TRUY VẾT IPTABLES TRÊN WORKER 1..."
echo "Tìm kiếm luật KUBE-SERVICES cho ClusterIP $CLUSTER_IP:"
SVC_CHAIN=$(run_w1 sudo iptables -t nat -L KUBE-SERVICES -n | grep $CLUSTER_IP | awk '{print $1}')
echo "-> Chuỗi xử lý (SVC Chain): $SVC_CHAIN"

echo "Danh sách các nhánh rẽ chia tải (SEP Chains - Round Robin) bên trong $SVC_CHAIN:"
run_w1 sudo iptables -t nat -L $SVC_CHAIN -n | grep KUBE-SEP

echo -e "\n[4/4] 🌐 KIỂM TRA NODEPORT..."
echo "Chuyển Service thành kiểu NodePort:"
run_cp kubectl patch svc nginx -p '{"spec": {"type": "NodePort"}}' >/dev/null 2>&1
NODE_PORT=$(run_cp kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
echo "-> NodePort được cấp: $NODE_PORT"

W1_IP=$(multipass info worker1 | grep IPv4 | awk '{print $2}')
W2_IP=$(multipass info worker2 | grep IPv4 | awk '{print $2}')

echo "Test truy cập vào IP của worker1 ($W1_IP:$NODE_PORT):"
curl -s --max-time 2 http://$W1_IP:$NODE_PORT | grep -o "Welcome to nginx!"

echo "Test truy cập vào IP của worker2 ($W2_IP:$NODE_PORT):"
curl -s --max-time 2 http://$W2_IP:$NODE_PORT | grep -o "Welcome to nginx!"

echo "=================================================="
echo "✅ HOÀN TẤT BÀI KIỂM TRA TẬP 3."
echo "Bạn có thể dọn dẹp bằng lệnh: multipass exec controlplane -- kubectl delete deploy nginx svc nginx"
echo "=================================================="
