# 📚 Lab Module 1: Nền tảng K8s Networking (Phase I)

Module này bao gồm 6 tập học, đi từ mô hình mạng cốt lõi của Kubernetes cho đến bảo mật mạng. Đây là **nền tảng bắt buộc** trước khi bước vào Module 2 (CNI Deep Dive).

## 📂 Cấu trúc thư mục

| Thư mục | Tên tập | Nội dung trọng tâm |
| :--- | :--- | :--- |
| [`1.1-network-model-pod/`](./1.1-network-model-pod) | Tập 1: Network Model & Bí mật bên trong Pod | 4 nguyên tắc không NAT, Pause container, veth pair |
| [`1.2-cni-specification/`](./1.2-cni-specification) | Tập 2: CNI Specification | Cơ chế ADD/DEL/GC, luồng `.conflist`, cnitool |
| [`1.3-kube-proxy-services/`](./1.3-kube-proxy-services) | Tập 3: Kube-proxy & Services | EndpointSlice, iptables chains, IPVS, nftables |
| [`1.4-dns-ndots/`](./1.4-dns-ndots) | Tập 4: DNS & Thuế "ndots" | CoreDNS, Headless Service, NodeLocal DNSCache |
| [`1.5-ingress-gateway-api/`](./1.5-ingress-gateway-api) | Tập 5: Ingress & Gateway API | ingress-nginx, HTTPRoute, Gateway API v1.4 |
| [`1.6-network-policy/`](./1.6-network-policy) | Tập 6: NetworkPolicy | Default-deny, AdminNetworkPolicy, lỗi drop DNS |

## ✅ Yêu cầu tiên quyết
- Đã hoàn thành **Module 0** và có cluster 3 nodes đang chạy (CNI chưa cài hoặc đã cài Flannel).
- Có thể SSH vào các node bằng Vagrant hoặc Multipass.
- Đã làm quen với `kubectl get`, `kubectl describe`, `kubectl exec`.
