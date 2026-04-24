# Lab 1.4: Bắt DNS Query & Triển khai NodeLocal DNSCache

## 🎯 Mục tiêu
- Dùng `tcpdump` / `netshoot` để quan sát trực tiếp "thuế ndots:5".
- Triển khai NodeLocal DNSCache và so sánh số lượng DNS query.

---

## 🔬 Bước 1: Quan sát file resolv.conf bên trong Pod

```bash
# Tạo Pod netshoot để debug
kubectl run debug-dns --image=nicolaka/netshoot -it --rm -- bash

# Bên trong Pod:
cat /etc/resolv.conf
# nameserver 10.96.0.10
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5
```

---

## 🔬 Bước 2: Bắt DNS query trực tiếp bằng tcpdump

```bash
# Terminal 1: SSH vào Node, bắt gói tin DNS trên interface CoreDNS
vagrant ssh worker1
sudo tcpdump -i any -nn port 53 -l

# Terminal 2: Từ trong Pod, thực hiện lookup một domain ngoài
kubectl exec -it debug-dns -- nslookup google.com
```

**Quan sát:** Trong terminal 1, đếm số lượng DNS query được gửi đi. Bạn sẽ thấy 4 query trước khi có kết quả từ `google.com`.

---

## 🔬 Bước 3: Bắt query bằng netshoot (dễ hơn)

```bash
# Trong Pod netshoot, dùng ngrep để xem DNS packet
ngrep -d eth0 -q port 53

# Terminal khác: curl một domain ngoài
kubectl exec debug-dns -- curl -s -o /dev/null https://github.com

# Quan sát output ngrep: đếm số AAAA và A query
```

---

## 🔬 Bước 4: Fix ndots và so sánh

```bash
# Tạo Pod với ndots thấp hơn
kubectl run debug-ndots2 --image=nicolaka/netshoot \
  --overrides='{"spec":{"dnsConfig":{"options":[{"name":"ndots","value":"2"}]}}}' \
  -it --rm -- bash

# Lặp lại Bước 2-3 với Pod này và đếm lại số DNS query
```

---

## 🔬 Bước 5: Triển khai NodeLocal DNSCache

```bash
# Download manifest
curl -Lo nodelocaldns.yaml https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml

# Lấy ClusterIP của kube-dns
KUBEDNS=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
echo "CoreDNS ClusterIP: $KUBEDNS"

# Thay thế các placeholder trong manifest
sed -i "s/__PILLAR__DNS__SERVER__/$KUBEDNS/g" nodelocaldns.yaml
sed -i "s/__PILLAR__LOCAL__DNS__/169.254.20.10/g" nodelocaldns.yaml
sed -i "s/__PILLAR__DNS__DOMAIN__/cluster.local/g" nodelocaldns.yaml

# Deploy
kubectl apply -f nodelocaldns.yaml

# Kiểm tra DaemonSet
kubectl get pods -n kube-system -l k8s-app=node-local-dns -o wide
```

---

## 🔬 Bước 6: Kiểm tra NodeLocal DNSCache hoạt động

```bash
# Trên Node, kiểm tra interface link-local được tạo
ip addr show nodelocaldns
# inet 169.254.20.10/32 scope link

# Sau khi DNS cache hoạt động, Pod mới sẽ có resolv.conf trỏ về 169.254.20.10
# Tạo Pod mới và kiểm tra
kubectl run debug-after --image=nicolaka/netshoot -it --rm -- cat /etc/resolv.conf
# nameserver 169.254.20.10  ← Giờ trỏ về local cache!
```

---

## ✅ Câu hỏi kiểm tra

1. Với `ndots:5`, khi query `github.com` có bao nhiêu DNS query được gửi đi?
2. NodeLocal DNSCache dùng IP gì và tại sao IP này không bao giờ bị conflict?
3. Cache miss thì NodeLocal DNSCache sẽ forward query đến đâu?

---

## 🧹 Dọn dẹp

```bash
kubectl delete pod debug-dns debug-ndots2 2>/dev/null || true
# Giữ NodeLocal DNSCache cho các Lab sau
```
