# 📺 Danh sách 42 Tập — Khóa học Kubernetes Networking & NetworkPolicy
## Kênh: @NetworkThucChien

---

## ⚪ PHẦN 0: NỀN TẢNG KUBERNETES NETWORKING (Tập 1–5)

### Tập 1 — Kubernetes Network Model: 4 nguyên tắc không NAT bạn phải thuộc lòng
> **Mô tả ngắn:** K8s yêu cầu mọi Pod giao tiếp trực tiếp không qua NAT — nhưng Linux kernel không tự làm điều đó. Tập này giải thích 4 nguyên tắc cốt lõi và tại sao chúng đặt ra thách thức lớn cho việc cài mạng.
>
> **Tags:** `#kubernetes` `#networking` `#k8s` `#CNI` `#devops`

---

### Tập 2 — Pod Network: Pause Container, veth pair & Network Namespace hoạt động ra sao
> **Mô tả ngắn:** Mỗi Pod có 1 network namespace riêng — nhưng ai tạo ra nó? Pause container làm gì? veth pair nối Pod vào Node như thế nào? Tập này mổ xẻ từ tầng Linux kernel.
>
> **Tags:** `#kubernetes` `#linux` `#namespace` `#veth` `#container`

---

### Tập 3 — Services & kube-proxy: ClusterIP, NodePort, LoadBalancer từ góc nhìn packet
> **Mô tả ngắn:** ClusterIP không phải là IP thật — không interface nào có nó. kube-proxy dùng iptables/IPVS để "đánh lừa" packet đi đúng hướng. Xem packet đi qua từng chain như thế nào.
>
> **Tags:** `#kubernetes` `#kube-proxy` `#iptables` `#services` `#networking`

---

### Tập 4 — CoreDNS & Thuế "ndots:5": Tại sao mỗi request trong K8s tốn 5 DNS query?
> **Mô tả ngắn:** Gọi `api.external.com` từ trong Pod K8s? DNS resolver thử 5 tên miền khác nhau trước khi tìm ra đúng cái. Đây là "thuế ngầm" ẩn trong mọi K8s cluster — và cách giảm nó.
>
> **Tags:** `#kubernetes` `#DNS` `#CoreDNS` `#performance` `#ndots`

---

### Tập 5 — CNI là gì? Hành trình cắm mạng cho Pod từ ADD đến DEL
> **Mô tả ngắn:** Khi kubelet tạo Pod, ai cắm mạng cho nó? CNI spec định nghĩa 4 động từ ADD/DEL/GC/STATUS — và plugin chain hoạt động ra sao. Lab: gọi CNI thủ công bằng `cnitool`.
>
> **Tags:** `#kubernetes` `#CNI` `#networking` `#kubelet` `#plugin`

---

## 🟡 PHẦN 1: FLANNEL (Tập 6–10)

### Tập 6 — Flannel là gì? Vấn đề Pod-to-Pod Communication mà nó giải quyết
> **Mô tả ngắn:** Không có CNI, Pod ở 2 Node khác nhau không thể nói chuyện. Flannel tạo ra một "flat network" ảo — mọi Pod thấy nhau như cùng mạng. Nhưng cái giá phải trả là gì?
>
> **Tags:** `#flannel` `#kubernetes` `#CNI` `#overlay` `#networking`

---

### Tập 7 — Kiến trúc Flannel: flanneld, etcd và CNI plugin hoạt động ra sao
> **Mô tả ngắn:** flanneld chạy trên mỗi node, lấy subnet assignment từ etcd, rồi cấu hình kernel để route traffic. CNI plugin là mắt xích cuối cùng nối Pod vào mạng. Tập này vẽ sơ đồ đầy đủ.
>
> **Tags:** `#flannel` `#etcd` `#kubernetes` `#architecture` `#CNI`

---

### Tập 8 — VXLAN Backend: Flannel đóng gói packet như thế nào? (50 bytes overhead)
> **Mô tả ngắn:** Flannel VXLAN bọc packet gốc vào UDP frame mới — thêm 50 bytes header. Lab: dùng `tcpdump` bắt và phân tích VXLAN packet trực tiếp, xem FDB table trên Linux.
>
> **Tags:** `#flannel` `#VXLAN` `#overlay` `#tcpdump` `#MTU`

---

### Tập 9 — host-gw Mode: Khi nào bỏ encapsulation để tăng tốc?
> **Mô tả ngắn:** host-gw không đóng gói packet — dùng routing table OS để forward thẳng. Nhanh hơn VXLAN nhưng yêu cầu tất cả Node cùng L2 segment. Khi nào chọn cái nào?
>
> **Tags:** `#flannel` `#host-gw` `#performance` `#routing` `#L2`

---

### Tập 10 — Giới hạn của Flannel: Tại sao không có NetworkPolicy?
> **Mô tả ngắn:** Flannel chỉ lo cắm mạng — không quan tâm Pod nào được nói chuyện với Pod nào. Hacker vào được 1 Pod là đi khắp cluster. Đây là lý do bạn cần CNI khác cho production.
>
> **Tags:** `#flannel` `#security` `#NetworkPolicy` `#kubernetes` `#lateral-movement`

---

## 🔵 PHẦN 2: CALICO (Tập 11–23)

### Tập 11 — Lateral Movement & Blast Radius: Bài toán bảo mật Flannel bỏ qua
> **Mô tả ngắn:** Lateral movement là kỹ thuật hacker dùng để di chuyển từ Pod bị xâm nhập sang các service khác trong cluster. Blast radius đo mức độ thiệt hại tối đa. Calico sinh ra để giới hạn cả hai.
>
> **Tags:** `#calico` `#security` `#NetworkPolicy` `#kubernetes` `#zerotrust`

---

### Tập 12 — Kiến trúc Calico: Felix, BIRD, Datastore — Ai làm gì?
> **Mô tả ngắn:** Felix là bộ não dịch NetworkPolicy thành iptables/eBPF rules. BIRD là BGP daemon quảng bá route. Datastore (K8s API hoặc etcd) lưu toàn bộ cấu hình. Tập này vẽ đầy đủ component diagram.
>
> **Tags:** `#calico` `#architecture` `#Felix` `#BGP` `#kubernetes`

---

### Tập 13 — iptables vs eBPF Dataplane trong Calico: O(n) vs O(1)
> **Mô tả ngắn:** iptables duyệt rules tuyến tính — 1000 rules = 1000 bước. eBPF dùng hash map — tìm kiếm O(1) bất kể số lượng. Và khi update, eBPF atomic — không gián đoạn traffic.
>
> **Tags:** `#calico` `#eBPF` `#iptables` `#performance` `#dataplane`

---

### Tập 14 — veth pair & conntrack: Hành trình của 1 packet qua Calico
> **Mô tả ngắn:** Từ khi Pod A gửi SYN đến lúc Pod B nhận được — packet đi qua những gì? veth pair, conntrack table, iptables chains Calico cài. Vẽ đường đi từng bước với `tcpdump` thực tế.
>
> **Tags:** `#calico` `#packet-flow` `#conntrack` `#iptables` `#debug`

---

### Tập 15 — NetworkPolicy cơ bản: Default Deny và Ingress Policy
> **Mô tả ngắn:** Không có NetworkPolicy = mọi Pod nói chuyện tự do. `podSelector: {}` + không có rules = default deny toàn bộ ingress. Tập này xây policy từ zero, kiểm tra từng bước bằng `netcat`.
>
> **Tags:** `#NetworkPolicy` `#calico` `#kubernetes` `#security` `#defaultdeny`

---

### Tập 16 — Cross-namespace Policy: AND vs OR — Dấu gạch "-" quan trọng thế nào!
> **Mô tả ngắn:** Trong YAML NetworkPolicy, cùng indent = AND (cả 2 điều kiện phải đúng). Thêm dấu `-` = OR (1 trong 2 là đủ). Sai 1 dấu gạch = policy hoạt động hoàn toàn sai. Bug phổ biến nhất khi viết policy.
>
> **Tags:** `#NetworkPolicy` `#calico` `#kubernetes` `#YAML` `#cross-namespace`

---

### Tập 17 — Union Logic: NetworkPolicy hoạt động như Security Group, không phải ACL
> **Mô tả ngắn:** Nhiều NetworkPolicy cùng select 1 Pod thì cộng hưởng — không phủ nhau. Giống Security Group AWS: thêm rule = mở thêm, không bao giờ đóng lại cái đã mở. Hiểu sai điểm này = lỗ hổng bảo mật.
>
> **Tags:** `#NetworkPolicy` `#kubernetes` `#security` `#union-logic` `#SecurityGroup`

---

### Tập 16 — BGP trong Calico: Node-to-Node Mesh và chuyển từ VXLAN
> **Mô tả ngắn:** Calico có thể dùng BGP thuần — không encapsulation, không overhead. Thiết lập BGP session trực tiếp giữa các Node (Node-to-Node Mesh), tự động định tuyến phẳng qua cổng vật lý và cách scale bằng Route Reflector (RR).
>
> **Tags:** `#calico` `#BGP` `#RouteReflector` `#routing` `#performance`

---

### Tập 17 — WireGuard trong Calico: Mã hóa traffic nội bộ & bẫy MTU 1440 bytes
> **Mô tả ngắn:** WireGuard mã hóa traffic giữa các Node — bảo mật tuyệt đối, tự động key rotation. Nhưng thêm 60 bytes header và cờ DF=1 dễ gây ra lỗi MTU Black Hole. Cách tính toán và cấu hình MTU đúng đắn.
>
> **Tags:** `#calico` `#WireGuard` `#encryption` `#MTU` `#security`

---

### Tập 18 — Lab 1: Bẫy "Pod thiếu label" — Connection Timeout không rõ lý do
> **Mô tả ngắn:** Thực hành gỡ lỗi connection timeout chéo Node trên Production. Điều tra tại sao Policy allow-rule không match Pod do thiếu nhãn, Felix không tạo rule allow trong iptables khiến traffic bị drop âm thầm.
>
> **Tags:** `#calico` `#lab` `#debug` `#NetworkPolicy` `#troubleshooting`

---

### Tập 19 — Lab 2: Sự cố kết nối từ Máy chủ ngoài vào cụm Kubernetes BGP
> **Mô tả ngắn:** BGP session giữa các Node UP hoàn toàn nhưng máy chủ giám sát bare-metal bên ngoài không thể kết nối tới Pod IP. Khắc phục bằng Static Route qua Node trung chuyển hoặc BGP Peer động.
>
> **Tags:** `#calico` `#BGP` `#lab` `#routing` `#troubleshooting`

---

### Tập 20 — Lab 3: Sự cố truyền nhận file dung lượng lớn qua WireGuard (MTU Black Hole)
> **Mô tả ngắn:** Upload file dung lượng nhỏ hoạt động bình thường, nhưng upload file lớn (>5MB) bị treo (hang) hoàn toàn chéo Node. Thực hành chẩn đoán ping với cờ DF=1, sửa đổi FelixConfiguration MTU 1440 và MSS Clamping.
>
> **Tags:** `#calico` `#WireGuard` `#MTU` `#PMTUD` `#lab`

---

### Tập 21 — Lab 4: Sự cố phân quyền truy cập chéo Namespace (Logic AND vs OR)
> **Mô tả ngắn:** Lỗi cú pháp YAML dấu gạch ngang tạo logic OR thay vì AND cho phép truy cập quá rộng, bị che giấu bởi lỗi thiếu nhãn Namespace (Bug Masking). Thực hành sửa logic AND và thiết lập ma trận kiểm thử an toàn.
>
> **Tags:** `#calico` `#NetworkPolicy` `#lab` `#cross-namespace` `#prometheus`

---

### Tập 22 — Tổng kết & Workflow Troubleshooting Calico chuẩn
> **Mô tả ngắn:** Tổng hợp quy trình troubleshooting Calico 5 bước chuẩn, phân biệt rạch ròi Control Plane vs Data Plane. Đúc kết bộ công cụ gỡ lỗi cheatsheet từ calicoctl, ip route, iptables-save đến tcpdump.
>
> **Tags:** `#calico` `#troubleshooting` `#debug` `#kubernetes` `#networking`

---

### Tập 23 — Calico Observability: Prometheus + Grafana + AlertManager
> **Mô tả ngắn:** Calico expose metrics qua Felix. Tập này build stack monitoring hoàn chỉnh: scrape metrics Felix qua ServiceMonitor, thiết lập Grafana Dashboard giám sát BGP sessions, packet drop và tự động cảnh báo qua AlertManager.
>
> **Tags:** `#calico` `#prometheus` `#grafana` `#monitoring` `#observability`

---

## 🟣 PHẦN 3: CILIUM (Tập 24–40)

### Tập 24 — Tại sao Cilium? Pain points của Calico & sockops bypass
> **Mô tả ngắn:** Calico có 3 vấn đề: observability phải tự build, iptables vẫn tồn tại dù bật eBPF, và packet vẫn đi full network stack. Cilium giải quyết cả 3 — Hubble built-in, eBPF thuần, sockops bypass 3-5x nhanh hơn.
>
> **Tags:** `#cilium` `#eBPF` `#kubernetes` `#CNI` `#performance`

---

### Tập 25 — BPF Maps: Hash, LRU, Array, Per-CPU — Vũ khí hiệu năng của Cilium
> **Mô tả ngắn:** BPF Maps là cấu trúc dữ liệu trong kernel — Policy lookup O(1) thay vì O(n) của iptables. Per-CPU map không cần lock — scale tuyến tính như ASIC multi-core. Hiểu Maps = hiểu tại sao Cilium nhanh.
>
> **Tags:** `#cilium` `#eBPF` `#BPFMaps` `#kernel` `#performance`

---

### Tập 26 — Kiến trúc Cilium: Operator, Agent, GoBGP, Hubble — So sánh với Calico
> **Mô tả ngắn:** Calico dùng BIRD (process riêng) cho BGP — Cilium embed GoBGP ngay trong Agent. Calico cần tự cài Prometheus — Cilium có Hubble built-in. Bảng so sánh component 1-1 giúp chuyển đổi tư duy từ Calico sang Cilium.
>
> **Tags:** `#cilium` `#calico` `#architecture` `#kubernetes` `#CNI`

---

### Tập 27 — 3 Hook Points của eBPF: XDP, TC và sockops — Mỗi cái làm gì?
> **Mô tả ngắn:** XDP hook ngay tại driver network card — sớm nhất, dùng cho DDoS protection. TC hook sau khi packet vào kernel — dùng cho policy enforcement. sockops hook tại socket — bypass toàn bộ network stack cho traffic cùng Node.
>
> **Tags:** `#cilium` `#eBPF` `#XDP` `#TC` `#sockops`

---

### Tập 28 — Cùng Node vs Khác Node: Tại sao sockops bypass hoàn toàn XDP/TC?
> **Mô tả ngắn:** Pod A và Pod B cùng Node: sockops kết nối thẳng socket-to-socket, XDP và TC không chạy. Khác Node: TC egress → XDP ingress → TC ingress — 3 điểm kiểm tra, Zero Trust. BPF Maps survive Agent restart = không mất traffic.
>
> **Tags:** `#cilium` `#eBPF` `#sockops` `#performance` `#zerotrust`

---

### Tập 29 — L3/L4 Policy trong Cilium: So sánh với Kubernetes NetworkPolicy
> **Mô tả ngắn:** CiliumNetworkPolicy là superset của Kubernetes NetworkPolicy — cú pháp tương tự nhưng thêm endpoint selector, entity (world, cluster, host). Migrate policy từ K8s NetworkPolicy sang CiliumNetworkPolicy từng bước.
>
> **Tags:** `#cilium` `#NetworkPolicy` `#CiliumNetworkPolicy` `#kubernetes` `#security`

---

### Tập 30 — L7 Policy: Chặn HTTP POST theo path với Envoy Proxy
> **Mô tả ngắn:** Kubernetes NetworkPolicy chỉ hiểu IP và port. Cilium hiểu HTTP method, URL path, gRPC service. Cơ chế: Cilium redirect traffic L7 qua Envoy Proxy (userspace) để inspect. Demo: allow GET /api nhưng deny POST /api/admin.
>
> **Tags:** `#cilium` `#L7` `#HTTP` `#Envoy` `#NetworkPolicy`

---

### Tập 31 — DNS Policy với toFQDNs: Filter theo domain thay vì IP — CDN multi-IP trap
> **Mô tả ngắn:** Chặn theo IP không hiệu quả với CDN (1 domain = hàng trăm IP thay đổi liên tục). `toFQDNs` filter theo domain name — DNS Proxy intercept response, track tất cả IP trả về, tự cleanup khi TTL hết.
>
> **Tags:** `#cilium` `#DNS` `#toFQDNs` `#security` `#egress`

---

### Tập 32 — Cilium + Istio: Khi nào kết hợp, khi nào dùng Cilium thuần?
> **Mô tả ngắn:** Greenfield project: dùng Cilium thuần — L7 policy + mTLS không cần Istio. Đã có Istio trong production: giữ Istio lo L7, Cilium lo L3/L4 — tận dụng eBPF để tăng performance cho Istio. Khi nào migrate hoàn toàn?
>
> **Tags:** `#cilium` `#istio` `#servicemesh` `#kubernetes` `#architecture`

---

### Tập 33 — Hubble CLI: `hubble observe` — Debug real-time không cần SSH vào Pod
> **Mô tả ngắn:** `hubble observe` stream flow logs real-time: Pod name, namespace, L7 info (HTTP method + path), Verdict (FORWARDED/DROPPED), Drop reason. Filter theo namespace, label, verdict. Debug nhanh gấp 10 lần so với `tcpdump`.
>
> **Tags:** `#cilium` `#hubble` `#observability` `#debug` `#kubernetes`

---

### Tập 34 — Hubble UI: Service Map tự động & DROPPED màu đỏ
> **Mô tả ngắn:** Hubble UI tự vẽ service dependency map từ actual traffic — không cần config thủ công. Flow bị DROP hiển thị màu đỏ với lý do ngay trên graph. Demo: phát hiện misconfigured NetworkPolicy chỉ bằng cách nhìn vào UI.
>
> **Tags:** `#cilium` `#hubble` `#UI` `#servicemap` `#observability`

---

### Tập 35 — Hubble Metrics: hubble_drop_total, http_requests — Đúng tool, đúng tình huống
> **Mô tả ngắn:** 3 tình huống, 3 tool khác nhau: 3 giờ sáng + alert = AlertManager. Security audit tuần = Hubble UI. Debug 1 Pod cụ thể = `hubble observe`. Metrics quan trọng: `hubble_drop_total`, `hubble_http_requests_total`, `hubble_flows_processed`.
>
> **Tags:** `#cilium` `#hubble` `#prometheus` `#metrics` `#monitoring`

---

### Tập 36 — Troubleshooting Cilium: cilium status → hubble observe → cilium CLI
> **Mô tả ngắn:** Workflow debug Cilium chuẩn: `cilium status` xem tổng quan → `hubble observe` xem flow thực tế → `cilium` CLI deep dive endpoint/policy. Thực hành với 3 lab broken khác nhau, áp dụng workflow từng bước.
>
> **Tags:** `#cilium` `#troubleshooting` `#hubble` `#debug` `#kubernetes`

---

### Tập 37 — Lab 1: Pod label sai — Hubble show "Policy denied" ngay lập tức
> **Mô tả ngắn:** Symptom: connection timeout. Với Calico phải đoán mò. Với Cilium: `hubble observe` show ngay `DROPPED` + `Policy denied` + tên Pod + label thực tế. Root cause trong 30 giây: `app=web` thay vì `app=frontend`.
>
> **Tags:** `#cilium` `#lab` `#hubble` `#NetworkPolicy` `#troubleshooting`

---

### Tập 38 — Lab 2: L7 Policy thiếu HTTP method — HTTP 403 & quy trình confirm dev
> **Mô tả ngắn:** Frontend nhận HTTP 403 khi gọi `POST /api/orders`. Hubble show: `POST /api/orders → DENIED`. Root cause: policy chỉ allow GET. Quan trọng: không tự fix — confirm với dev team trước. Lesson về quy trình change management.
>
> **Tags:** `#cilium` `#L7` `#lab` `#HTTP403` `#process`

---

### Tập 39 — Lab 3: DNS Egress Policy & toFQDNs trap — External API fail bí ẩn
> **Mô tả ngắn:** App không gọi được external payment API. DNS resolve ok. HTTP request DROPPED. Root cause: thiếu `toFQDNs` egress rule cho `api.payment.com` port 443. Bonus: CDN có 50 IP khác nhau — `toFQDNs` track tất cả tự động.
>
> **Tags:** `#cilium` `#DNS` `#toFQDNs` `#lab` `#egress`

---

### Tập 40 — Lab 4: WireGuard MTU với Cilium — Hubble show "MTU exceeded" ngay!
> **Mô tả ngắn:** Upload file lớn fail — cùng triệu chứng như Lab Calico. Nhưng debug khác hoàn toàn: Hubble show `DROPPED → MTU exceeded` ngay lập tức, không cần ping test mò mẫm. Fix: `helm upgrade --set tunnel=wireguard --set mtu=1420`.
>
> **Tags:** `#cilium` `#WireGuard` `#MTU` `#lab` `#hubble`

---

## 🏆 PHẦN 4: KẾT (Tập 41–42)

### Tập 41 — So sánh 3 CNI: Flannel vs Calico vs Cilium — Bảng đánh giá toàn diện
> **Mô tả ngắn:** Bảng so sánh 8 tiêu chí: Dataplane, NetworkPolicy, BGP, Observability, Performance, Độ phức tạp, DNS Policy, L7 Policy. Không có CNI nào tốt nhất — chỉ có CNI phù hợp nhất với bài toán cụ thể.
>
> **Tags:** `#kubernetes` `#CNI` `#flannel` `#calico` `#cilium`

---

### Tập 42 — Decision Framework: Khi nào dùng Flannel, Calico, Cilium trong Production?
> **Mô tả ngắn:** Flowchart quyết định thực chiến: Dev/lab không cần NetworkPolicy → Flannel. Production cần policy + team quen BGP → Calico. Cần L7 policy hoặc observability built-in hoặc cluster lớn nhiều microservices → Cilium.
>
> **Tags:** `#kubernetes` `#CNI` `#production` `#architecture` `#decision`
