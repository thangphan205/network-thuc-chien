---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', 'Noto Sans', sans-serif;
    font-size: 22px;
    background: #0d1721ff;
    color: #e2e8f0;
  }
  h1 { color: #a78bfa; font-size: 2em; margin-bottom: 0.3em; }
  h2 { color: #34d399; font-size: 1.4em; border-bottom: 2px solid #34d399; padding-bottom: 0.2em; }
  h3 { color: #fbbf24; font-size: 1.1em; }
  code { background: #1a1a35; color: #a0e4b8; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1a1a35; border-left: 4px solid #a78bfa; padding: 16px; border-radius: 6px; }
  pre code { color: #a0e4b8; background: transparent; padding: 0; }
  .hljs-keyword, .hljs-selector-tag { color: #ff79c6; }
  .hljs-string, .hljs-addition { color: #f1fa8c; }
  .hljs-attr, .hljs-attribute { color: #79b8ff; }
  .hljs-number, .hljs-literal { color: #bd93f9; }
  .hljs-comment { color: #6272a4; font-style: italic; }
  .hljs-variable, .hljs-template-variable { color: #ffb86c; }
  .hljs-built_in, .hljs-name, .hljs-type { color: #50fa7b; }
  .hljs-meta { color: #ff5555; }
  .hljs-title, .hljs-section { color: #8be9fd; }
  .hljs-bullet, .hljs-symbol { color: #ffb86c; }
  .hljs-params, .hljs-subst { color: #e2e8f0; }
  .hljs-deletion { color: #ff5555; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
  th { background: #2d1b69; color: #e9d5ff; padding: 10px 14px; font-weight: 600; letter-spacing: 0.03em; }
  td { padding: 8px 14px; border-bottom: 1px solid #2a2050; color: #e2e8f0; background: #151530; }
  tr:nth-child(even) td { background: #1e1e40; }
  tr:hover td { background: #2a2050; }
  blockquote { border-left: 4px solid #fbbf24; padding-left: 16px; color: #b0bcd0; font-style: italic; margin: 12px 0; }
  ul li, ol li { margin-bottom: 6px; line-height: 1.6; }
  section.title {
    background: linear-gradient(135deg, #0d1021 0%, #1a1040 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
    padding: 60px 80px;
  }
  section.title h1 { font-size: 2.6em; color: #a78bfa; border: none; }
  section.title h2 { font-size: 1.2em; color: #34d399; border: none; margin-top: 0.2em; }
  section.title p { color: #a0aec0; font-size: 0.9em; margin-top: 16px; }
  section.divider {
    background: linear-gradient(135deg, #1a1040 0%, #0d1021 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    text-align: center;
  }
  section.divider h1 { font-size: 2.5em; border: none; }
  section.divider h2 { border: none; color: #a0aec0; }
  section.ep {
    background: linear-gradient(135deg, #0d1021 0%, #12103a 100%);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
    padding: 60px 80px;
  }
  section.ep h1 { font-size: 1.8em; color: #a78bfa; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; margin-top: 0.3em; }
  section.ep p { color: #94a3b8; font-size: 0.9em; margin-top: 12px; }
---

<!-- _class: title -->

# Kubernetes Networking
## Thực chiến từ CNI đến NetworkPolicy

**Network Thực Chiến** · 45 Tập · 4 Phần · Flannel → Calico → Cilium

---

## Tại sao khóa học này khác?

Hầu hết tài liệu K8s networking dừng ở mức "cài Flannel xong, chạy được rồi".

```
❌ Không giải thích tại sao Pod trên 2 Node khác nhau nói chuyện được
❌ Không nói về rủi ro bảo mật khi không có NetworkPolicy
❌ Không demo cách debug khi mạng K8s bị lỗi
❌ Không so sánh tại sao chọn Calico hay Cilium cho production
```

**Khóa học này đi thẳng vào cơ chế:**

> Từ Linux kernel namespace, veth pair, iptables chains → đến BGP routing, eBPF maps, L7 policy — xem thực tế bằng `tcpdump`, `hubble observe`, `calicoctl`.

---

## Lộ trình 45 Tập

| Phần | Tập | Nội dung |
| :--- | :--- | :--- |
| **⚪ Phần 0** | 1–5 | Nền tảng K8s Networking |
| **🟡 Phần 1** | 6–10 | Flannel — Flat Network & VXLAN |
| **🔵 Phần 2** | 11–26 | Calico — NetworkPolicy, BGP, WireGuard |
| **🟣 Phần 3** | 27–43 | Cilium — eBPF, L7 Policy, Hubble |
| **🏆 Phần 4** | 44–45 | So sánh & Decision Framework |

**Môi trường lab:** Full VM (Vagrant + VirtualBox hoặc Multipass trên macOS M-series)

> Không dùng `kind` hay `minikube` — cần xem `tcpdump`, `ip route`, `iptables` thực sự trên kernel.

---

## Phần 0: Nền tảng (Tập 1–5)

| # | Tiêu đề |
| :--- | :--- |
| 1 | Kubernetes Network Model: 4 nguyên tắc không NAT |
| 2 | Pod Network: Pause Container, veth pair & Network Namespace |
| 3 | Services & kube-proxy: ClusterIP, NodePort, LoadBalancer từ góc nhìn packet |
| 4 | CoreDNS & Thuế "ndots:5" |
| 5 | CNI là gì? Hành trình cắm mạng cho Pod từ ADD đến DEL |

---

## Phần 1–2: Flannel & Calico (Tập 6–26)

| # | Tiêu đề |
| :--- | :--- |
| 6–10 | Flannel: Flat Network, VXLAN, host-gw, giới hạn |
| 11–13 | Calico: Tại sao cần, Felix/BIRD, iptables vs eBPF |
| 14 | Calico Packet Flow: veth pair & conntrack |
| 15–17 | NetworkPolicy: Default Deny, AND/OR, Union Logic |
| 18–20 | BGP: Autonomous System, Full Mesh vs RR, WireGuard MTU |
| 21–25 | Troubleshooting + 4 Labs thực chiến |
| 26 | Calico Observability: Prometheus + Grafana |

---

## Phần 3–4: Cilium & Kết (Tập 27–45)

| # | Tiêu đề |
| :--- | :--- |
| 27–29 | Cilium: Tại sao, BPF Maps, Architecture |
| 30–31 | eBPF Dataplane: XDP, TC, sockops |
| 32–35 | CiliumNetworkPolicy: L3/L4, L7, DNS, Istio |
| 36–38 | Hubble: CLI, UI, Metrics |
| 39–43 | Troubleshooting + 4 Labs thực chiến |
| 44 | So sánh 3 CNI: Flannel vs Calico vs Cilium |
| 45 | Decision Framework: Khi nào dùng cái nào? |

---

<!-- _class: divider -->

# ⚪ Phần 0
## Nền tảng Kubernetes Networking

---

<!-- _class: ep -->

# Tập 1
## Kubernetes Network Model: 4 nguyên tắc không NAT bạn phải thuộc lòng

`#k8s` `#networking` `#CNI` `#model`

---

## Tập 1 — 4 Nguyên tắc K8s Networking

K8s **không cài mạng** — chỉ đặt ra 4 quy tắc CNI plugin phải tuân theo:

```
Nguyên tắc 1: Pod-to-Pod không NAT
  └── Pod A (192.168.1.5) → Pod B (192.168.2.7): giao tiếp trực tiếp

Nguyên tắc 2: Node-to-Pod không NAT
  └── Worker node ping Pod IP: không qua NAT

Nguyên tắc 3: Pod thấy đúng IP nguồn của người gọi
  └── Không bị masquerade thành IP khác

Nguyên tắc 4: Pod IP là unique trong toàn cluster
  └── Không có 2 Pod cùng IP dù ở 2 Node khác nhau
```

> **Vấn đề:** Linux kernel mặc định KHÔNG đảm bảo 4 điều này. Đây là lý do CNI tồn tại.

---

## Tập 1 — Tại sao không NAT lại khó?

**Mô hình mạng thông thường (có NAT):**
```
Pod A (10.244.1.5) ─── NAT ──► Node IP (192.168.1.10) ──► Pod B
```
Pod B thấy IP nguồn là `192.168.1.10` (IP Node), không phải IP Pod A.

**Mô hình K8s (không NAT):**
```
Pod A (10.244.1.5) ─────────────────────────────────────► Pod B (10.244.2.8)
```
Pod B thấy đúng `10.244.1.5` — nhưng 2 Pod ở 2 Node khác nhau, làm sao packet biết đường đi?

**Đây là bài toán CNI phải giải:** tạo ra mạng ảo phẳng vượt qua ranh giới Node.

---

<!-- _class: ep -->

# Tập 2
## Pod Network: Pause Container, veth pair & Network Namespace hoạt động ra sao

`#linux` `#namespace` `#veth` `#pause`

---

## Tập 2 — Pause Container & Network Namespace

Mỗi Pod trong K8s không phải là 1 container — mà là **nhóm container chia sẻ 1 network namespace**.

```
┌─────────────────────────────────────────┐
│              POD                        │
│  ┌──────────┐  ┌──────────┐            │
│  │  pause   │  │  app     │   Chia sẻ: │
│  │ container│  │ container│   - eth0   │
│  │ (infra)  │  │          │   - lo     │
│  └──────────┘  └──────────┘   - PID ns │
│         Network Namespace               │
└─────────────────────────────────────────┘
```

**Pause container làm gì?**
- Tạo và giữ network namespace sống
- Nếu app container crash và restart → network namespace vẫn tồn tại
- App container "join" vào namespace của pause qua `--network=container:<pause_id>`

---

## Tập 2 — veth pair nối Pod vào Node

```
  POD namespace          Node namespace (root)
  ┌──────────┐           ┌─────────────────────┐
  │  eth0    │◄─────────►│  vethXXXXXX         │
  │ (10.244. │  veth     │  (no IP, bridge)    │
  │  1.5)    │  pair     │         │           │
  └──────────┘           │    cni0 bridge       │
                         │    (10.244.1.1)      │
                         └─────────────────────┘
```

### Lab: Inspect namespace Pod từ Worker Node

```bash
# Tìm PID của pause container
PAUSE_PID=$(crictl inspect $(crictl ps | grep pause | awk '{print $1}') | jq '.info.pid')

# Xem network interface bên trong namespace Pod
nsenter -t $PAUSE_PID -n ip addr
nsenter -t $PAUSE_PID -n ip route

# Xem veth pair tương ứng trên node
ip link show | grep veth
```

---

<!-- _class: ep -->

# Tập 3
## Services & kube-proxy: ClusterIP, NodePort, LoadBalancer từ góc nhìn packet

`#kube-proxy` `#iptables` `#services` `#IPVS`

---

## Tập 3 — ClusterIP không phải IP thật

```bash
kubectl get svc nginx
# NAME    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
# nginx   ClusterIP   10.96.123.45   <none>        80/TCP    1d
```

`10.96.123.45` — không có interface nào có IP này. Không `ping` được. **Đó là VIP ảo.**

| Loại | Cơ chế | Dùng khi |
| :--- | :--- | :--- |
| **ClusterIP** | VIP ảo trong cluster, iptables DNAT | Internal service |
| **NodePort** | Mở port trên mọi Node (30000–32767) | Expose ra ngoài đơn giản |
| **LoadBalancer** | Cần Cloud LB controller tạo LB thật | Production, cloud |

---

## Tập 3 — kube-proxy & iptables chain flow

```
Client → PREROUTING → KUBE-SERVICES → KUBE-SVC-XXXX
                                            │
                             ┌──────────────┼──────────────┐
                             ▼              ▼              ▼
                       KUBE-SEP-1    KUBE-SEP-2    KUBE-SEP-3
                       (Pod 1 IP)    (Pod 2 IP)    (Pod 3 IP)
                         DNAT          DNAT          DNAT
```

### Lab: Xem iptables rules của một Service

```bash
# Tìm chain tương ứng với service
CHAIN=$(iptables -t nat -L KUBE-SERVICES -n | grep "10.96.123.45" | awk '{print $3}')

# Xem endpoints (Pod IPs thật)
iptables -t nat -L $CHAIN -n --line-numbers

# Verify với conntrack khi có traffic
conntrack -L | grep 10.96.123.45
```

---

<!-- _class: ep -->

# Tập 4
## CoreDNS & Thuế "ndots:5": Tại sao mỗi request tốn 5 DNS query?

`#CoreDNS` `#DNS` `#ndots` `#performance`

---

## Tập 4 — Thuế ndots:5 giải thích

File `/etc/resolv.conf` trong mọi Pod K8s:

```
nameserver 10.96.0.10       # CoreDNS ClusterIP
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

**ndots:5** nghĩa là: nếu tên miền có **ít hơn 5 dấu chấm**, thử từng search domain trước khi tra DNS ngoài.

```
Gọi api.external.com (2 dấu chấm < 5):

Query 1: api.external.com.default.svc.cluster.local → NXDOMAIN
Query 2: api.external.com.svc.cluster.local         → NXDOMAIN
Query 3: api.external.com.cluster.local             → NXDOMAIN
Query 4: api.external.com.                          → ✅ FOUND
```

**3 query thừa cho mỗi external call!**

---

## Tập 4 — Fix & NodeLocal DNSCache

**Cách fix đơn giản:** thêm dấu chấm cuối (FQDN)
```bash
curl https://api.external.com.   # Chỉ 1 query
```

**Cách fix dứt điểm:** NodeLocal DNSCache tại IP tĩnh `169.254.20.10`

```
Pod → 169.254.20.10 (local cache, link-local)
         │── Hit  ──► Trả lời ngay (microseconds)
         └── Miss ──► CoreDNS → upstream DNS
```

**Lợi ích:**
- Giảm tải CoreDNS đáng kể
- Tránh conntrack race condition cho UDP DNS
- P99 latency DNS giảm 10–50x

```bash
# Kiểm tra query count trước/sau
kubectl exec -it netshoot -- watch -n1 'dig +stats api.external.com | grep "Query time"'
```

---

<!-- _class: ep -->

# Tập 5
## CNI là gì? Hành trình cắm mạng cho Pod từ ADD đến DEL

`#CNI` `#kubelet` `#plugin` `#cnitool`

---

## Tập 5 — CNI Specification

CNI (Container Network Interface) là **hợp đồng** giữa kubelet và network plugin.

```
kubelet tạo Pod
    │
    ▼
Gọi CNI plugin với verb ADD
    │  Input (stdin): network config JSON
    │  Output (stdout): assigned IP, routes
    ▼
Plugin cắm mạng cho container
    │  Tạo veth pair
    │  Gán IP từ IPAM
    │  Cài routes
    ▼
Pod có network ✅
```

**4 động từ CNI v1.1.0:**

| Verb | Khi nào | Tác dụng |
| :--- | :--- | :--- |
| `ADD` | Pod tạo mới | Cắm mạng, gán IP |
| `DEL` | Pod xóa | Gỡ mạng, release IP |
| `GC` | Cleanup | Xóa stale network objects |
| `STATUS` | Health check | Kiểm tra plugin còn sống |

---

## Tập 5 — Lab: Gọi CNI thủ công bằng cnitool

```bash
# Cài cnitool
go install github.com/containernetworking/cni/cnitool@latest

# Tạo config CNI đơn giản (bridge mode)
cat > /etc/cni/net.d/10-mynet.conflist <<EOF
{
  "cniVersion": "1.1.0",
  "name": "mynet",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "ipam": { "type": "host-local", "subnet": "10.99.0.0/24" }
    },
    { "type": "portmap", "capabilities": {"portMappings": true} }
  ]
}
EOF

# Tạo network namespace và gọi CNI ADD
ip netns add test-ns
CNI_PATH=/opt/cni/bin cnitool add mynet /var/run/netns/test-ns

# Xem IP được gán
ip netns exec test-ns ip addr

# Cleanup
CNI_PATH=/opt/cni/bin cnitool del mynet /var/run/netns/test-ns
```

---

<!-- _class: divider -->

# 🟡 Phần 1
## Flannel — Flat Network & VXLAN

---

<!-- _class: ep -->

# Tập 6
## Flannel là gì? Vấn đề Pod-to-Pod Communication mà nó giải quyết

`#flannel` `#CNI` `#overlay` `#flat-network`

---

## Tập 6 — Vấn đề không có CNI

```bash
# Cài K8s không cài CNI → Node trạng thái NotReady
kubectl get nodes
# NAME     STATUS     ROLES           AGE
# master   NotReady   control-plane   2m
# worker1  NotReady   <none>          1m
```

**Tại sao NotReady?** kubelet chờ CNI plugin — không có plugin thì Pod không có IP, không có network.

**Thử ping giữa 2 Node:**
```
Node 1 (eth0: 192.168.1.10)    Node 2 (eth0: 192.168.1.11)
Pod A: 10.244.1.5              Pod B: 10.244.2.7

Ping 10.244.2.7 từ Pod A → FAIL
Route table không có 10.244.2.0/24 → packet bị drop
```

**Flannel giải quyết:** tạo "flat network" ảo — Pod A thấy Pod B như cùng mạng, dù ở Node khác.

---

<!-- _class: ep -->

# Tập 7
## Kiến trúc Flannel: flanneld, etcd và CNI plugin hoạt động ra sao

`#flannel` `#etcd` `#architecture` `#subnet`

---

## Tập 7 — Kiến trúc Flannel

```
                    etcd / K8s API
                    (subnet registry)
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
    flanneld (N1)   flanneld (N2)   flanneld (N3)
    10.244.1.0/24  10.244.2.0/24  10.244.3.0/24
          │
          ▼
    CNI plugin ── kubelet ── Pod
```

**Luồng hoạt động:**

1. `flanneld` khởi động → đăng ký subnet `/24` riêng với etcd
2. etcd lưu mapping: `Node IP → Pod subnet`
3. Khi Pod tạo → kubelet gọi CNI plugin → gán IP trong subnet của Node đó
4. `flanneld` cập nhật route/FDB table để forward packet đúng Node

---

<!-- _class: ep -->

# Tập 8
## VXLAN Backend: Flannel đóng gói packet như thế nào? (50 bytes overhead)

`#flannel` `#VXLAN` `#encapsulation` `#tcpdump`

---

## Tập 8 — VXLAN Packet Structure

**VXLAN bọc packet gốc vào UDP:**

```
Outer Ethernet | Outer IP | UDP 8472 | VXLAN Header | Inner Ethernet | Inner IP | Payload
   14 bytes      20 bytes   8 bytes     8 bytes          14 bytes      20 bytes
                                                    ──────────────────────────────
                              Tổng overhead: ~50 bytes
```

**Hệ quả:**
- MTU 1500 → payload thực tế chỉ còn 1450 bytes
- TCP MSS tự động giảm xuống 1410 nhờ MTU 1450 để tránh fragmentation

### Lab: VTEP & Bắt VXLAN bằng tcpdump

```bash
# 1. Verify cấu hình VTEP (VNI = 1, port 8472, local IP)
ip -d link show flannel.1

# 2. Bắt traffic VXLAN trên interface vật lý (cổng 8472)
tcpdump -i eth0 -n udp port 8472 -v

# Phân tích: thấy outer IP header + inner IP header
# Inner header chứa IP của Pod nguồn và đích
tcpdump -i eth0 -n udp port 8472 -X | head -60

# Xem FDB table (VTEP mapping)
bridge fdb show dev flannel.1
```

---

<!-- _class: ep -->

# Tập 9
## host-gw Mode: Khi nào bỏ encapsulation để tăng tốc?

`#flannel` `#host-gw` `#routing` `#performance`

---

## Tập 9 — host-gw vs VXLAN

**host-gw mode:** không đóng gói — dùng routing table OS forward thẳng.

```
Node1 (192.168.1.10)                Node2 (192.168.1.11)
Pod A: 10.244.1.5                   Pod B: 10.244.2.7

Routing table Node1:
  10.244.2.0/24 via 192.168.1.11 dev eth0  ← Flannel thêm route này
```

**So sánh:**

| | VXLAN | host-gw |
| :--- | :--- | :--- |
| Encapsulation | ✅ UDP wrap | ❌ Không |
| MTU overhead | 50 bytes | 0 bytes |
| Điều kiện | Bất kỳ topology | **Phải cùng L2 segment** |
| Throughput | Thấp hơn ~10% | Tốt hơn |
| Latency | Cao hơn ~20% | Thấp hơn |

**Khi nào dùng host-gw?** Cluster on-premise, tất cả Node cùng switch L2, cần performance cao.

**Khi nào phải dùng VXLAN?** Cloud (VPC routing khác L2), Node ở nhiều subnet khác nhau.

---

<!-- _class: ep -->

# Tập 10
## Giới hạn của Flannel: Tại sao không có NetworkPolicy?

`#flannel` `#security` `#NetworkPolicy` `#lateral-movement`

---

## Tập 10 — Flannel: Mạng có, bảo mật không

**Flannel chỉ giải quyết connectivity** — không quan tâm Pod nào được phép nói chuyện với Pod nào.

```
Cluster với Flannel:

Frontend Pod ──────────► Database Pod   ✅ (bình thường)
Hacker Pod  ──────────► Database Pod   ✅ (Flannel không chặn!)
Hacker Pod  ──────────► Payment API    ✅ (vẫn không chặn!)
```

**Kịch bản tấn công:**
```
1. Hacker exploit lỗ hổng Frontend → chiếm Frontend Pod
2. Từ Frontend Pod, scan toàn bộ Pod IPs trong cluster
3. Tấn công Database trực tiếp (không qua firewall nào)
4. Dump credentials → lateral movement sang mọi service
```

> Flannel không triển khai NetworkPolicy — nó delegate cho CNI khác hoặc bỏ qua.

**Giải pháp:** cần CNI có khả năng enforce NetworkPolicy → **Calico**, **Cilium**.

---

<!-- _class: divider -->

# 🔵 Phần 2
## Calico — NetworkPolicy, BGP & WireGuard

---

<!-- _class: ep -->

# Tập 11
## Lateral Movement & Blast Radius: Bài toán bảo mật Flannel bỏ qua

`#calico` `#security` `#lateral-movement` `#blast-radius`

---

## Tập 11 — Lateral Movement trong K8s

**Lateral movement:** Kẻ tấn công từ 1 Pod bị chiếm → di chuyển sang các service khác.

```
[Bước 1] Exploit Frontend → chiếm 1 Pod
[Bước 2] Scan: nmap 10.244.0.0/16 -p 3306,5432,6379,8080
[Bước 3] Tìm thấy: database (3306), redis (6379), internal API
[Bước 4] Tấn công trực tiếp — không có gì chặn
```

**Blast Radius:** Phạm vi thiệt hại tối đa từ 1 Pod bị compromise.

| CNI | Blast Radius |
| :--- | :--- |
| Flannel (không policy) | **Toàn bộ cluster** |
| Calico + default deny | **Chỉ service Pod đó có quyền truy cập** |

**Calico giải quyết bằng NetworkPolicy:**
```
NetworkPolicy: Frontend chỉ được gọi Backend port 8080
               Backend chỉ được gọi Database port 5432
               Không ai khác → DEFAULT DENY
```

---

<!-- _class: ep -->

# Tập 12
## Kiến trúc Calico: Felix, BIRD, Datastore — Ai làm gì?

`#calico` `#felix` `#BIRD` `#BGP` `#architecture`

---

## Tập 12 — Component Diagram

```
┌─────────────────────────────────────────────────────┐
│                  Kubernetes API / etcd              │
│           (NetworkPolicy, IPPool, BGPPeer)          │
└─────────────────────┬───────────────────────────────┘
                      │ watch
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │  Felix   │ │   BIRD   │ │  Typha   │
    │(per node)│ │(per node)│ │(optional)│
    │          │ │          │ │          │
    │ Policy → │ │ BGP peer │ │ Cache K8s│
    │ iptables │ │ với node │ │ API cho  │
    │ / eBPF   │ │ khác     │ │ Felix    │
    └──────────┘ └──────────┘ └──────────┘
```

**Felix:** Nhận NetworkPolicy từ K8s API → dịch thành iptables rules hoặc eBPF programs.
Event-driven: thay đổi policy → Felix cập nhật ngay lập tức, không cần restart.

**BIRD:** BGP daemon — quảng bá Pod CIDR của Node mình ra các Node khác (hoặc ToR switch).

**Typha (tùy chọn):** Cache K8s API — giảm tải API server khi cluster lớn (>100 nodes).

---

<!-- _class: ep -->

# Tập 13
## iptables vs eBPF Dataplane trong Calico: O(n) vs O(1)

`#calico` `#eBPF` `#iptables` `#performance` `#dataplane`

---

## Tập 13 — Tại sao iptables không scale?

**iptables duyệt rules tuyến tính:**

```
Packet đến → Rule 1? No → Rule 2? No → Rule 3? No → ... → Rule 5000? Yes → ACCEPT
```

- 1000 Pod = ~10.000 iptables rules
- Mỗi packet phải check từng rule từ đầu
- Thêm rule = phải **rewrite toàn bộ chain** (không atomic)

**eBPF dùng BPF Hash Map:**

```
Packet đến → Hash lookup {src_ip, dst_ip, port} → O(1) → ACCEPT/DROP
```

| | iptables | eBPF |
| :--- | :--- | :--- |
| Lookup | O(n) — tuyến tính | **O(1) — hash map** |
| Update | Rewrite full chain | **Atomic swap** |
| Downtime khi update | Có (vài ms) | **Không** |
| Conntrack | Linux conntrack | **eBPF per-flow state** |

---

## Tập 13 — Bật eBPF trong Calico

```bash
# Kiểm tra eBPF dataplane hiện tại
calicoctl get felixconfig default -o yaml | grep bpfEnabled

# Bật eBPF (cần K8s 5.3+ kernel)
kubectl patch felixconfiguration default \
  --patch '{"spec": {"bpfEnabled": true}}'

# Verify — eBPF programs được load vào interfaces
tc filter show dev eth0 ingress
# filter protocol all pref 1 bpf chain 0
#   filter protocol all pref 1 bpf chain 0 handle 0x1 calico_to_host_ep [...]

# Tắt kube-proxy (eBPF Calico thay thế)
kubectl patch ds kube-proxy -n kube-system \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico": "true"}}}}}'
```

---

<!-- _class: ep -->

# Tập 14
## veth pair & conntrack: Hành trình của 1 packet qua Calico

`#calico` `#packet-flow` `#conntrack` `#veth` `#debug`

---

## Tập 14 — Hành trình đầy đủ của 1 packet

```
Pod A (10.244.1.5)
    │
    │ eth0 (trong Pod namespace)
    ▼
vethXXXXX (trên Node, nối vào bridge/route)
    │
    ▼
iptables FORWARD chain
    ├── KUBE-FORWARD
    ├── cali-FORWARD  ◄── Calico chain kiểm tra policy
    │       └── cali-from-wl-dispatch
    │               └── cali-fw-XXXX (rule của Pod A)
    ▼
Routing table → qua eth0 Node → đến Node 2
    ▼
iptables INPUT chain trên Node 2
    └── cali-to-wl-dispatch → cali-tw-XXXX (rule của Pod B)
    ▼
Pod B (10.244.2.7) ✅
```

### Lab: Trace packet với iptables LOG

```bash
# Thêm rule LOG để thấy packet đi qua chain nào
iptables -t filter -I cali-FORWARD 1 -j LOG --log-prefix "CALICO-FWD: "
tail -f /var/log/kern.log | grep CALICO-FWD
```

---

<!-- _class: ep -->

# Tập 15
## NetworkPolicy cơ bản: Default Deny và Ingress Policy

`#NetworkPolicy` `#calico` `#default-deny` `#ingress`

---

## Tập 15 — Default Deny

```yaml
# Chặn TẤT CẢ ingress vào namespace "production"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}      # Select TẤT CẢ pods
  policyTypes:
  - Ingress            # Không có ingress rules = deny all ingress
```

```bash
# Verify: frontend không còn reach được backend
kubectl exec -n production frontend -- curl http://backend:8080
# curl: (7) Failed to connect: Connection timeout
```

---

## Tập 15 — Allow cụ thể

```yaml
# Chỉ cho frontend gọi backend port 8080
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

```bash
# Test từng hướng
kubectl exec -n production frontend -- nc -zv backend 8080   # ✅ OK
kubectl exec -n production frontend -- nc -zv backend 5432   # ❌ DROP
kubectl exec -n production attacker -- nc -zv backend 8080   # ❌ DROP
```

---

<!-- _class: ep -->

# Tập 16
## Cross-namespace Policy: AND vs OR — Dấu gạch "-" quan trọng thế nào!

`#NetworkPolicy` `#cross-namespace` `#AND` `#OR` `#YAML`

---

## Tập 16 — AND vs OR trong NetworkPolicy

**OR logic** (mỗi điều kiện là một item riêng với dấu `-`):
```yaml
ingress:
- from:
  - namespaceSelector:        # ← Điều kiện 1: HOẶC namespace "monitoring"
      matchLabels:
        name: monitoring
  - podSelector:              # ← Điều kiện 2: HOẶC pod có label "role: scraper"
      matchLabels:
        role: scraper
# Kết quả: namespace monitoring ĐỌC được, HOẶC bất kỳ pod có role=scraper đọc được
# (Bao gồm cả pod role=scraper trong namespace khác!)
```

**AND logic** (cùng indent, không có dấu `-` ở giữa):
```yaml
ingress:
- from:
  - namespaceSelector:        # ← Điều kiện 1 AND
      matchLabels:
        name: monitoring
    podSelector:              # ← Điều kiện 2 (cùng item, không có dấu -)
      matchLabels:
        role: scraper
# Kết quả: PHẢI là pod có role=scraper VÀ nằm trong namespace monitoring
```

> **Quy tắc:** Cùng `from` item (không có `-`) = AND. Khác `from` item (có `-`) = OR.

---

<!-- _class: ep -->

# Tập 17
## Union Logic: NetworkPolicy hoạt động như Security Group, không phải ACL

`#NetworkPolicy` `#union-logic` `#SecurityGroup` `#kubernetes`

---

## Tập 17 — Nhiều Policy = Cộng hưởng (không phủ nhau)

**Security Group AWS:** thêm rule = mở thêm. Không có rule nào "đóng" cái đã mở.
**NetworkPolicy K8s:** giống hệt — đây là **allowlist thuần túy**.

```yaml
# Policy 1: Frontend → Backend port 8080
# Policy 2: Monitoring → Backend port 9090 (metrics)
# Policy 3: Database → Backend port 8080 (callback)
```

Kết quả: Backend nhận được từ Frontend (8080), Monitoring (9090), Database (8080).
Không policy nào "ghi đè" hay "xung đột" với policy khác.

**Hệ quả quan trọng:**
```
Nếu muốn DENY cụ thể: phải dùng AdminNetworkPolicy (API mới)
hoặc Calico GlobalNetworkPolicy với action: Deny

NetworkPolicy cơ bản KHÔNG có cơ chế DENY tường minh —
chỉ có "không có rule" = deny (khi đã có policy selector Pod đó).
```

---

<!-- _class: ep -->

# Tập 18
## BGP trong Calico: Cluster như một Autonomous System, peer với ToR Switch

`#calico` `#BGP` `#AS` `#datacenter` `#routing`

---

## Tập 18 — Calico BGP Architecture

**Mặc định Calico dùng VXLAN hoặc IPIP.** BGP mode bỏ encapsulation hoàn toàn.

```
Datacenter L3 Fabric:

ToR Switch (AS 65000)
├── BGP peer ◄──────────────────────────────────────┐
│                                                    │
├── Node 1 (AS 64512, BIRD)    ←──── advertise: 10.244.1.0/24
│   Pod CIDR: 10.244.1.0/24
│
├── Node 2 (AS 64512, BIRD)    ←──── advertise: 10.244.2.0/24
│   Pod CIDR: 10.244.2.0/24
│
└── Node 3 (AS 64512, BIRD)    ←──── advertise: 10.244.3.0/24
    Pod CIDR: 10.244.3.0/24
```

**Ưu điểm BGP thuần:**
- Không encapsulation → không overhead → throughput tốt nhất
- ToR switch có routing table đầy đủ → server bare-metal ngoài cluster ping được Pod IP
- Standard BGP → tích hợp dễ với datacenter network hiện có

---

<!-- _class: ep -->

# Tập 19
## Full Mesh vs Route Reflector: Bài toán n*(n-1)/2 khi cluster lớn

`#calico` `#BGP` `#RouteReflector` `#scaling`

---

## Tập 19 — BGP Full Mesh vs Route Reflector

**Full Mesh:** mỗi Node peer với mọi Node khác.

```
3 nodes:  3 sessions    (3×2/2)
10 nodes: 45 sessions   (10×9/2)
100 nodes: 4950 sessions ← ❌ không scale
```

**Route Reflector:** tập trung route qua vài node RR.

```
100 nodes, 2 RR:
└── 100 nodes × 2 RR sessions = 200 sessions ✅

[Node 1] ──┐
[Node 2] ──┤
[Node 3] ──┤──► [Route Reflector] ──► [Node 4, 5, 6...]
[Node ...] ─┘
```

```yaml
# Label 2 nodes làm Route Reflector
kubectl label node rr1 calico-route-reflector=true
kubectl label node rr2 calico-route-reflector=true

# BGPPeer cho regular nodes peer với RR
calicoctl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: peer-with-rr
spec:
  nodeSelector: "!has(calico-route-reflector)"
  peerSelector: "has(calico-route-reflector)"
EOF
```

---

<!-- _class: ep -->

# Tập 20
## WireGuard trong Calico: Mã hóa traffic nội bộ & bẫy MTU 1440 bytes

`#calico` `#WireGuard` `#encryption` `#MTU` `#PMTUD`

---

## Tập 20 — WireGuard Overlay

```bash
# Bật WireGuard encryption (cần kernel 5.6+)
kubectl patch felixconfiguration default \
  --patch '{"spec": {"wireguardEnabled": true}}'

# Verify: interface wireguard.cali xuất hiện trên mỗi node
ip link show wireguard.cali
# wireguard.cali: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 ...
```

**Tại sao MTU là 1420 (không phải 1500)?**

```
Physical MTU: 1500 bytes
 └── WireGuard header: 60 bytes
      ├── UDP header: 8 bytes
      ├── IP header: 20 bytes
      └── WireGuard overhead: 32 bytes
 
Payload thực tế: 1500 - 60 = 1440 bytes

Calico set MTU = 1420 (buffer thêm 20 bytes cho an toàn)
```

**Bẫy DF bit (PMTUD Black Hole):**
```
TCP segment 1460 bytes + DF=1 → router cần fragment nhưng không được
→ Router drop packet SILENTLY → TCP connection hang
→ File nhỏ ok (fit trong 1420), file lớn fail
```

**Fix:** `wireguardMTU: 1420` + MSS Clamping via iptables.

---

<!-- _class: ep -->

# Tập 21
## Troubleshooting Calico: calicoctl → ip route → iptables-save

`#calico` `#troubleshooting` `#debug` `#methodology`

---

## Tập 21 — Workflow Debug Calico

```
Symptom: Pod A không reach Pod B

Bước 1: Kiểm tra BGP (nếu dùng BGP mode)
────────────────────────────────────────────
calicoctl node status
# BGP Summary:
# peer Node2: ESTABLISHED ✅   hoặc IDLE ❌

Bước 2: Kiểm tra routing table
────────────────────────────────────────────
ip route show | grep 10.244.2    # Pod B subnet
# 10.244.2.0/24 via 192.168.1.11 dev eth0 ← OK
# (nếu không có route này → BGP chưa quảng bá)

Bước 3: Kiểm tra iptables rules
────────────────────────────────────────────
iptables-save | grep -A5 "cali-fw-<interface-pod-A>"
# Tìm rule ACCEPT hoặc DROP tương ứng

Bước 4: Debug với tcpdump
────────────────────────────────────────────
# Trên Node của Pod B, bắt traffic đến Pod B
tcpdump -i any host 10.244.2.7 -n
```

---

<!-- _class: ep -->

# Tập 22
## Lab 1: Bẫy "Pod thiếu label" — Connection Timeout không rõ lý do

`#calico` `#lab` `#label` `#debug` `#NetworkPolicy`

---

## Tập 22 — Lab 1: Setup & Symptom

```bash
# Setup: Deploy backend với NetworkPolicy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
spec:
  podSelector:
    matchLabels:
      app: backend        # Policy này select pod có label app=backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
EOF

# Tạo pod backend KHÔNG có label
kubectl run backend --image=nginx    # ← Không có --labels="app=backend"

# Test từ frontend
kubectl exec frontend -- curl http://backend-svc:8080
# curl: (7) Failed to connect to backend-svc port 8080: Connection timed out
```

---

## Tập 22 — Lab 1: Root Cause & Fix

**Phân tích:**
```bash
# Kiểm tra labels của pod backend
kubectl get pod backend --show-labels
# NAME      READY   STATUS    LABELS
# backend   1/1     Running   <none>   ← KHÔNG có app=backend!

# NetworkPolicy select podSelector app=backend
# → Pod backend không match selector
# → Felix KHÔNG tạo rule allow cho pod này
# → Default: nếu có policy trong namespace → DENY
```

**Fix:**
```bash
kubectl label pod backend app=backend

# Felix tự động detect thay đổi label → update iptables ngay lập tức
# Không cần restart gì

# Verify lại
kubectl exec frontend -- curl -s http://backend-svc:8080
# 200 OK ✅
```

**Lesson:** Felix event-driven — thay đổi label → update policy ngay. Không cần rollout.

---

<!-- _class: ep -->

# Tập 23
## Lab 2: BGP không quảng bá Pod CIDR — Server vật lý không ping được Pod

`#calico` `#BGP` `#lab` `#routing` `#troubleshooting`

---

## Tập 23 — Lab 2: BGP Missing Route

```bash
# Symptom: Server bare-metal ngoài cluster không ping được Pod
ping 10.244.1.5   # từ server vật lý
# PING 10.244.1.5: 100% packet loss

# Kiểm tra BGP trên Node
calicoctl node status
# Calico process is running.
# IPv4 BGP status
# +──────────────┬────────────+────────────────────+──────────+
# | PEER ADDRESS | PEER TYPE  | STATE | SINCE      | INFO     |
# +──────────────┬────────────+────────────────────+──────────+
# | 192.168.1.1  | ToR Switch | up    | 2024-01-01 | Idle ❌ |

# Kiểm tra BGP config
calicoctl get bgpconfiguration default -o yaml
# serviceClusterIPs: []   ← Pod CIDR chưa khai báo!
```

```bash
# Fix: Thêm Pod CIDR vào BGPConfiguration
calicoctl patch bgpconfiguration default \
  --patch '{"spec": {"serviceClusterIPs": [{"cidr": "10.244.0.0/16"}]}}'

# Verify: Server vật lý có route chưa
ip route | grep 10.244   # trên ToR switch hoặc server
# 10.244.0.0/16 via 192.168.1.10 ✅
```

---

<!-- _class: ep -->

# Tập 24
## Lab 3: WireGuard MTU & PMTUD Black Hole — File nhỏ ok, file lớn fail

`#calico` `#WireGuard` `#MTU` `#PMTUD` `#lab`

---

## Tập 24 — Lab 3: MTU Black Hole

```bash
# Symptom: Transfer file 100KB OK, file 10MB fail
curl -o /dev/null http://backend/small-file.bin    # OK ✅
curl -o /dev/null http://backend/large-file.bin    # Hang mãi ❌

# Diagnose: Check MTU trên wireguard interface
ip link show wireguard.cali
# wireguard.cali: mtu 1500   ← Sai! Phải là 1420

# Xác nhận: gửi packet lớn với DF bit
ping -s 1400 -M do 10.244.2.7
# PING 10.244.2.7 56(1428) bytes of data.
# From 10.244.1.1: Frag needed ← router báo cần fragment

ping -s 1450 -M do 10.244.2.7
# (không có phản hồi) ← PMTUD Black Hole!
```

```bash
# Fix 1: Set MTU đúng cho WireGuard
kubectl patch felixconfiguration default \
  --patch '{"spec": {"wireguardMTU": 1420}}'

# Fix 2: MSS Clamping để TCP tự điều chỉnh
iptables -t mangle -A FORWARD \
  -p tcp --tcp-flags SYN,RST SYN \
  -j TCPMSS --clamp-mss-to-pmtu
```

---

<!-- _class: ep -->

# Tập 25
## Lab 4: Cross-namespace AND/OR Bug — Prometheus không scrape được Backend

`#calico` `#NetworkPolicy` `#cross-namespace` `#prometheus` `#lab`

---

## Tập 25 — Lab 4: 2 Bug cùng lúc

```bash
# Symptom: Prometheus (namespace: monitoring) không scrape backend
# Metrics endpoint trả về Connection refused

# Policy có vẻ đúng:
kubectl get networkpolicy backend-metrics -n production -o yaml
```

```yaml
# Policy hiện tại (BUG!)
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: monitoring
  - podSelector:              # ← Bug 1: Có dấu "-" → OR, không phải AND!
      matchLabels:
        role: prometheus
```

```yaml
# Fix Bug 1: Bỏ dấu "-" để thành AND
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: monitoring
    podSelector:              # ← Không có dấu "-" → AND ✅
      matchLabels:
        role: prometheus
```

```bash
# Bug 2: Namespace monitoring chưa có label "name: monitoring"
kubectl get namespace monitoring --show-labels
# NAME        LABELS: <none>   ← Thiếu label!

kubectl label namespace monitoring name=monitoring
# Phải fix cả 2 bug cùng lúc mới hoạt động
```

---

<!-- _class: ep -->

# Tập 26
## Calico Observability: Prometheus + Grafana + AlertManager miễn phí

`#calico` `#prometheus` `#grafana` `#monitoring` `#observability`

---

## Tập 26 — Felix Metrics

Calico Felix expose metrics qua HTTP `/metrics` (port 9091 mặc định):

```bash
# Bật felix metrics
kubectl patch felixconfiguration default \
  --patch '{"spec": {"prometheusMetricsEnabled": true}}'

# Các metric quan trọng
curl http://localhost:9091/metrics | grep -E "felix_bgp|felix_denied|felix_active"

# felix_bgp_peers_total        — số BGP peer đang ESTABLISHED
# felix_denied_packets_total   — packet bị NetworkPolicy drop (alert khi tăng đột biến!)
# felix_active_local_endpoints — số Pod đang active trên node này
```

**4 Grafana Dashboards:**

| Dashboard | Mục đích |
| :--- | :--- |
| BGP Session Status | Số peer UP/DOWN theo thời gian |
| NetworkPolicy Flow Logs | Packet allowed vs denied |
| Pod Connectivity | Tỷ lệ kết nối thành công giữa các Pod |
| Node Network Performance | Throughput, latency per node |

```yaml
# AlertManager: alert khi BGP session down
- alert: CalicoBGPSessionDown
  expr: felix_bgp_peers_total{state="established"} < 1
  for: 2m
  annotations:
    summary: "Calico BGP session down on {{ $labels.node }}"
```

---

<!-- _class: divider -->

# 🟣 Phần 3
## Cilium — eBPF, L7 Policy & Hubble

---

<!-- _class: ep -->

# Tập 27
## Tại sao Cilium? Pain points của Calico & sockops bypass

`#cilium` `#eBPF` `#sockops` `#performance`

---

## Tập 27 — 3 Pain Points của Calico

```
Pain point 1: Observability phải tự build
  Calico: bạn tự cài Prometheus + Grafana + viết queries
  Cilium: Hubble built-in, UI có sẵn, metrics tự động

Pain point 2: iptables vẫn còn dù bật eBPF
  Calico eBPF: thay thế FORWARD chain nhưng iptables vẫn load trong kernel
  Cilium:      xóa iptables hoàn toàn — kernel bypass

Pain point 3: Traffic cùng Node vẫn qua network stack
  Calico: Pod A → veth → bridge → veth → Pod B (full stack)
  Cilium: Pod A socket ──sockops──► Pod B socket (bypass XDP/TC hoàn toàn)
          3-5x nhanh hơn cho intra-node traffic
```

**Thực tế benchmark (cùng Node):**

| | Latency (p99) | Throughput |
| :--- | :--- | :--- |
| Calico (eBPF) | ~120 µs | ~18 Gbps |
| Cilium (sockops) | **~35 µs** | **~48 Gbps** |

---

<!-- _class: ep -->

# Tập 28
## BPF Maps: Hash, LRU, Array, Per-CPU — Vũ khí hiệu năng của Cilium

`#cilium` `#eBPF` `#BPFMaps` `#kernel` `#performance`

---

## Tập 28 — 4 Loại BPF Map

BPF Maps là **cấu trúc dữ liệu trong kernel** — được chia sẻ giữa eBPF programs và user space (Cilium Agent).

| Map type | Key | Value | Dùng cho |
| :--- | :--- | :--- | :--- |
| **Hash Map** | {src_ip, dst_ip, port, proto} | Policy decision | Policy lookup O(1) |
| **LRU Hash Map** | {src_ip, sport, dst_ip, dport} | Connection state | Connection tracking |
| **Array Map** | Config index | Config value | Global config, counters |
| **Per-CPU Map** | (per core) | Stats | Throughput metrics không cần lock |

**Per-CPU Map = không lock:**
```
CPU 0 có map riêng ──┐
CPU 1 có map riêng ──┤──► Merge khi đọc từ user space
CPU 2 có map riêng ──┘

Kết quả: Scale tuyến tính với số CPU core
         Giống ASIC multi-core forwarding
```

```bash
# Xem BPF Maps đang chạy
bpftool map list
# 5: hash  name cilium_call_map  flags 0x0
# 8: lru_hash  name cilium_ct_any4  flags 0x0
# 12: array  name cilium_nodeport  flags 0x0
```

---

<!-- _class: ep -->

# Tập 29
## Kiến trúc Cilium: Operator, Agent, GoBGP, Hubble — So sánh với Calico

`#cilium` `#architecture` `#GoBGP` `#Hubble`

---

## Tập 29 — Cilium vs Calico Architecture

| Chức năng | Calico | Cilium |
| :--- | :--- | :--- |
| Policy enforcement | Felix (daemon riêng) | **Cilium Agent** |
| BGP daemon | BIRD (process riêng) | **GoBGP (embedded trong Agent)** |
| IP pool management | Calico IPAM | **Cilium Operator** |
| Observability | Tự cài Prometheus + Grafana | **Hubble built-in** |
| Data plane | iptables / eBPF | **Kernel eBPF thuần** |
| L7 policy | ❌ Không có | **✅ Envoy Proxy** |

```
Cilium Architecture:

┌─────────────────────────────────────────┐
│         Kubernetes API Server           │
└───────────────┬─────────────────────────┘
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
Cilium      Cilium        Hubble
Operator    Agent         Relay
(IP pool)   (per node)    (aggregation)
            ├── GoBGP          ├── CLI
            ├── eBPF loader    ├── UI
            └── BPF Maps       └── Prometheus
```

---

<!-- _class: ep -->

# Tập 30
## 3 Hook Points của eBPF: XDP, TC và sockops — Mỗi cái làm gì?

`#cilium` `#eBPF` `#XDP` `#TC` `#sockops`

---

## Tập 30 — eBPF Hook Points

```
NIC (Network Card)
    │
    ▼
[XDP hook] ← Sớm nhất: tại driver, trước khi cấp phát sk_buff
    │          Dùng cho: DDoS protection, packet drop tốc độ wire
    ▼
[TC hook]  ← Sau khi vào kernel network stack (tc ingress/egress)
    │          Dùng cho: policy enforcement, NAT, load balancing
    ▼
Network Stack (routing, conntrack...)
    │
    ▼
[sockops hook] ← Tại socket layer
               Dùng cho: cùng Node optimization, bypass stack hoàn toàn
```

**Cilium dùng cả 3:**
- **XDP:** drop DDoS traffic tốc độ cao nhất (triệu packets/giây per core)
- **TC:** enforce NetworkPolicy cho traffic vào/ra Pod (cả ingress lẫn egress)
- **sockops:** kết nối thẳng socket khi 2 Pod cùng Node

---

<!-- _class: ep -->

# Tập 31
## Cùng Node vs Khác Node: Tại sao sockops bypass hoàn toàn XDP/TC?

`#cilium` `#sockops` `#performance` `#same-node` `#zero-trust`

---

## Tập 31 — Same Node vs Different Node

**Cùng Node (sockops acceleration):**
```
Pod A socket
    │ [policy check ở sockops]
    ▼
Pod B socket   ← Kết nối thẳng, bypass XDP/TC/network stack hoàn toàn
```

**Khác Node (full eBPF path):**
```
Pod A
    │ TC egress   ← Check policy: Pod A có được gửi ra ngoài không?
    ▼
Node 1 network
    │ (qua vật lý/tunnel)
    ▼
Node 2
    │ XDP ingress ← Drop nhanh nếu không hợp lệ
    ▼
    │ TC ingress  ← Check policy: ai được vào Pod B?
    ▼
Pod B
```

**Zero Trust:** Cilium kiểm tra ở CẢ 2 đầu (egress Node1 + ingress Node2).

**BPF Maps survive Agent restart:**
```bash
# Restart Cilium Agent → traffic không gián đoạn
kubectl delete pod -n kube-system -l k8s-app=cilium
# BPF Maps vẫn trong kernel → connections không bị cắt
```

---

<!-- _class: ep -->

# Tập 32
## L3/L4 Policy trong Cilium: So sánh với Kubernetes NetworkPolicy

`#cilium` `#CiliumNetworkPolicy` `#L3` `#L4`

---

## Tập 32 — CiliumNetworkPolicy vs K8s NetworkPolicy

```yaml
# K8s NetworkPolicy (cơ bản)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
```

```yaml
# CiliumNetworkPolicy (superset — thêm entity, cidr, node)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-policy
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
  - fromEntities:
    - "cluster"   # Allow traffic từ bất kỳ đâu trong cluster
  egress:
  - toEntities:
    - "world"     # Allow egress ra internet
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
```

---

<!-- _class: ep -->

# Tập 33
## L7 Policy: Chặn HTTP POST theo path với Envoy Proxy

`#cilium` `#L7` `#HTTP` `#Envoy` `#NetworkPolicy`

---

## Tập 33 — L7 HTTP Policy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-l7-policy
spec:
  endpointSelector:
    matchLabels:
      app: api-server
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: GET
          path: "/api/.*"           # ✅ Allow GET bất kỳ /api/
        - method: POST
          path: "/api/orders"       # ✅ Allow POST /api/orders
        # POST /api/admin → ❌ DENIED (không có rule)
```

**Cơ chế:** Cilium redirect traffic L7 qua Envoy Proxy (userspace) để inspect.

```bash
# Verify với hubble
hubble observe --to-pod api-server --verdict DROPPED
# Mar 20 10:15:32 frontend → api-server POST /api/admin DROPPED
# Policy denied @ L7
```

---

<!-- _class: ep -->

# Tập 34
## DNS Policy với toFQDNs: Filter theo domain thay vì IP — CDN multi-IP trap

`#cilium` `#DNS` `#toFQDNs` `#egress` `#CDN`

---

## Tập 34 — Vấn đề với IP-based egress policy

**CDN như Cloudflare, Fastly:** 1 domain = hàng trăm IP thay đổi liên tục.

```bash
dig api.payment.com
# 104.18.23.45
# 104.18.24.67
# 172.64.145.89
# ... (thay đổi mỗi vài phút theo TTL)
```

IP-based policy phải list tất cả IPs → không thể maintain.

**toFQDNs giải quyết:**
```yaml
egress:
- toFQDNs:
  - matchName: "api.payment.com"
  toPorts:
  - ports:
    - port: "443"
      protocol: TCP
```

**Cơ chế DNS Proxy của Cilium:**
```
Pod gọi DNS api.payment.com
    ↓
Cilium DNS Proxy intercept response
    ↓
Track tất cả IPs trả về → lưu vào BPF Map
    ↓
Tự động allow traffic đến các IPs đó
    ↓
Khi TTL hết → cleanup BPF Map
```

---

<!-- _class: ep -->

# Tập 35
## Cilium + Istio: Khi nào kết hợp, khi nào dùng Cilium thuần?

`#cilium` `#istio` `#servicemesh` `#mTLS` `#architecture`

---

## Tập 35 — Cilium thuần vs Cilium + Istio

**Greenfield (không có Istio):** Dùng Cilium thuần túy.
```
Cilium đảm nhận:
├── L3/L4 NetworkPolicy (eBPF, nhanh)
├── L7 Policy (HTTP/gRPC/DNS qua Envoy sidecar-less)
├── mTLS giữa workloads (Cilium 1.14+)
└── Observability (Hubble)
```

**Đã có Istio trong production:** Giữ Istio + thêm Cilium.
```
Cilium lo: L3/L4 policy, eBPF data plane (nhanh)
Istio lo:  L7 policy, traffic management, mTLS đã có sẵn

Lợi ích kết hợp:
├── Cilium eBPF bypass iptables → Istio overhead giảm đáng kể
├── "Cilium + Istio" = CNCF blessed combination
└── Không cần migrate Istio config (rủi ro cao)
```

**Khi nào migrate hoàn toàn khỏi Istio?**
```
- Team thành thạo Cilium L7 policy
- Không cần traffic splitting (canary, A/B test)
- Hoặc dùng Argo Rollouts thay thế
- Cluster nhỏ/trung bình (< 50 services)
```

---

<!-- _class: ep -->

# Tập 36
## Hubble CLI: `hubble observe` — Debug real-time không cần SSH vào Pod

`#cilium` `#hubble` `#CLI` `#observability` `#debug`

---

## Tập 36 — hubble observe

```bash
# Cài Hubble CLI
cilium hubble enable
cilium hubble port-forward &

# Xem tất cả traffic real-time
hubble observe

# Ví dụ output:
# Mar 20 10:15:01 default/frontend → default/backend:8080 L4 TCP FORWARDED
# Mar 20 10:15:02 default/frontend → default/backend:8080 HTTP GET /api/v1 FORWARDED
# Mar 20 10:15:03 default/attacker → default/backend:8080 L4 TCP DROPPED

# Filter theo namespace
hubble observe --namespace production

# Filter chỉ DROPPED flows (debug mode)
hubble observe --verdict DROPPED

# Filter theo pod cụ thể
hubble observe --from-pod default/frontend --to-pod default/backend

# Xem L7 chi tiết (HTTP method, path, status code)
hubble observe --protocol http -o json | jq '.flow.l7.http'
```

**So sánh với tcpdump:**
- `tcpdump`: phải SSH vào Node, cần biết interface name, output raw bytes
- `hubble observe`: từ laptop, Pod name sẵn, HTTP info decode sẵn, filter dễ

---

<!-- _class: ep -->

# Tập 37
## Hubble UI: Service Map tự động & DROPPED màu đỏ

`#cilium` `#hubble` `#UI` `#servicemap` `#visualization`

---

## Tập 37 — Hubble UI

```bash
# Mở Hubble UI
cilium hubble ui
# Mở browser: http://localhost:12000
```

**Service Map tự động:**
- Hubble vẽ sơ đồ dependency từ **traffic thực tế** — không cần config thủ công
- Node = service/workload, Edge = traffic flow có chiều mũi tên
- Màu **xanh** = FORWARDED, màu **đỏ** = DROPPED

**Debug NetworkPolicy bằng UI:**
```
1. Thấy edge màu đỏ từ frontend → backend
2. Click vào edge → xem chi tiết flows bị DROP
3. Thấy: "Policy denied — no rule matching ingress"
4. Fix policy, reload UI → edge chuyển sang xanh ✅
```

**Filter trên UI:**
- Theo namespace, label, protocol
- Time range: 1 phút đến 24 giờ
- Verdict: ALL / FORWARDED / DROPPED / ERROR

> Hubble UI giúp phát hiện misconfigured NetworkPolicy trong vài giây — không cần `kubectl exec` hay `tcpdump`.

---

<!-- _class: ep -->

# Tập 38
## Hubble Metrics: hubble_drop_total, http_requests — Đúng tool, đúng tình huống

`#cilium` `#hubble` `#metrics` `#prometheus` `#monitoring`

---

## Tập 38 — Hubble Metrics & Đúng Tool

**Metrics quan trọng:**

```bash
# Số packet bị drop theo policy (alert khi tăng đột biến)
hubble_drop_total{direction="ingress",reason="Policy denied"}

# HTTP request rate và latency
hubble_http_requests_total{method="GET",protocol="HTTP/1.1"}
hubble_http_request_duration_seconds{quantile="0.99"}

# Tổng số flows được xử lý
hubble_flows_processed_total{type="L3/L4",verdict="FORWARDED"}
```

**3 tình huống, 3 tool:**

| Tình huống | Tool | Lý do |
| :--- | :--- | :--- |
| 3 giờ sáng, PagerDuty alert | **AlertManager** | Tự động, không cần ngồi xem |
| Security audit hàng tuần | **Hubble UI** | Nhìn tổng quan service map, tìm flows bất thường |
| Debug 1 Pod cụ thể đang lỗi | **`hubble observe`** | Real-time, filter chính xác, nhanh |

```bash
# Setup alert khi drop rate tăng
- alert: HighDropRate
  expr: rate(hubble_drop_total[5m]) > 100
  annotations:
    summary: "High packet drop rate — check NetworkPolicy"
```

---

<!-- _class: ep -->

# Tập 39
## Troubleshooting Cilium: cilium status → hubble observe → cilium CLI

`#cilium` `#troubleshooting` `#debug` `#methodology`

---

## Tập 39 — Workflow Debug Cilium

```bash
# Bước 1: Tổng quan cluster
cilium status
# KVStore:                Ok   etcd: 1/1 connected
# Kubernetes:             Ok   1.29 (v1.29.0)
# Cilium:                 Ok   1 health node
# NodeMonitor:            Disabled
# IPAM:                   Ok   X IPs available
# KubeProxyReplacement:   Strict   [eth0 (Direct Routing)]
# HostFirewall:           Disabled

# Bước 2: Xem flows thực tế
hubble observe --from-pod <ns>/<pod> --verdict DROPPED

# Bước 3: Inspect endpoint cụ thể
cilium endpoint list
cilium endpoint get <endpoint-id>

# Bước 4: Xem policy đang được enforce
cilium policy get

# Bước 5: Deep dive BPF
cilium bpf ct list global | grep <src-ip>   # Connection tracking
cilium bpf policy get <endpoint-id>          # Policy map
```

---

<!-- _class: ep -->

# Tập 40
## Lab 1: Pod label sai — Hubble show "Policy denied" ngay lập tức

`#cilium` `#lab` `#hubble` `#label` `#debug`

---

## Tập 40 — Lab 1: Label Bug với Hubble

```bash
# Symptom: frontend không gọi được backend
kubectl exec frontend -- curl http://backend:8080
# curl: (7) Connection timed out

# Với Calico: phải tcpdump mò mẫm
# Với Cilium: hubble biết ngay
hubble observe --from-pod default/frontend --verdict DROPPED

# Output ngay lập tức:
# Mar 20 10:20:01 default/frontend → default/backend:8080
#   L4 TCP DROPPED
#   Reason: Policy denied
#   Source labels: app=web, tier=frontend    ← Đây! app=web thay vì app=frontend
```

```bash
# Kiểm tra policy
cilium policy get | grep -A10 "to backend"
# endpointSelector: app=backend
# ingress from: app=frontend   ← Policy expect app=frontend

# Kiểm tra label thực tế của frontend pod
kubectl get pod frontend --show-labels
# LABELS: app=web,tier=frontend   ← Bug: app=web thay vì app=frontend

# Fix
kubectl label pod frontend app=frontend --overwrite

# Verify ngay với hubble
hubble observe --from-pod default/frontend
# Mar 20 10:20:45 default/frontend → default/backend:8080 HTTP GET / FORWARDED ✅
```

---

<!-- _class: ep -->

# Tập 41
## Lab 2: L7 Policy thiếu HTTP method — HTTP 403 & quy trình confirm dev

`#cilium` `#L7` `#lab` `#HTTP403` `#process`

---

## Tập 41 — Lab 2: L7 403 Forbidden

```bash
# Symptom: Frontend nhận 403 khi gọi POST /api/orders
kubectl exec frontend -- curl -X POST http://backend:8080/api/orders -d '{}'
# HTTP/1.1 403 Forbidden
# {"message": "Access denied by network policy"}

# Hubble thấy ngay
hubble observe --to-pod default/backend --protocol http
# Mar 20 10:25:01 frontend → backend POST /api/orders 403 Access denied DROPPED
#                                   ^              ^
#                              Method              Path rõ ràng

# Xem policy hiện tại
cilium policy get | grep -A20 "backend"
# http:
# - method: GET
#   path: "/api/.*"     ← Chỉ có GET, không có POST!
```

```bash
# QUAN TRỌNG: Không tự fix — confirm với dev team trước
# "Policy chỉ allow GET — POST /api/orders bị deny intentionally chưa?"

# Sau khi confirm: thêm POST
kubectl apply -f - <<EOF
# ... (policy YAML thêm POST /api/orders)
EOF

# Verify
hubble observe --to-pod default/backend --verdict FORWARDED
# POST /api/orders 200 FORWARDED ✅
```

---

<!-- _class: ep -->

# Tập 42
## Lab 3: DNS Egress Policy & toFQDNs trap — External API fail bí ẩn

`#cilium` `#DNS` `#toFQDNs` `#lab` `#egress`

---

## Tập 42 — Lab 3: DNS Egress Fail

```bash
# Symptom: Backend không gọi được external payment API
kubectl exec backend -- curl https://api.payment.com/charge
# curl: (6) Could not resolve host: api.payment.com
# Hoặc: curl: (7) Failed to connect

# Hubble diagnostic
hubble observe --from-pod default/backend

# Flow 1: DNS OK
# default/backend → kube-system/coredns:53 DNS api.payment.com? FORWARDED
# kube-system/coredns → default/backend DNS api.payment.com 104.18.23.45 FORWARDED

# Flow 2: HTTP DROPPED!
# default/backend → 104.18.23.45:443 L4 TCP DROPPED
# Reason: Policy denied — no egress rule
```

```bash
# Fix: Thêm toFQDNs egress rule
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
spec:
  endpointSelector:
    matchLabels:
      app: backend
  egress:
  - toFQDNs:
    - matchName: "api.payment.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
EOF
# Cilium DNS Proxy tự track tất cả IPs — bao gồm CDN IPs thay đổi liên tục ✅
```

---

<!-- _class: ep -->

# Tập 43
## Lab 4: WireGuard MTU với Cilium — Hubble show "MTU exceeded" ngay!

`#cilium` `#WireGuard` `#MTU` `#lab` `#hubble`

---

## Tập 43 — Lab 4: WireGuard MTU (Cilium vs Calico)

```bash
# Cùng triệu chứng như Lab Calico: file nhỏ OK, file lớn fail
kubectl exec frontend -- curl -o /dev/null http://backend/large.bin
# (hang mãi không có response)

# Với Calico: phải ping -M do mò MTU thủ công
# Với Cilium: Hubble thấy ngay nguyên nhân

hubble observe --from-pod default/frontend --verdict DROPPED
# Mar 20 11:00:01 default/frontend → default/backend:8080
#   L4 TCP DROPPED
#   Reason: MTU exceeded    ← Hiển thị ngay, không cần đoán!
#   Details: packet size 1480, MTU 1420

# Xem MTU hiện tại
ip link show cilium_wg0
# cilium_wg0: mtu 1500   ← Sai! WireGuard cần 1420

# Fix với helm
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set encryption.wireguard.enabled=true \
  --set tunnel=wireguard \
  --set mtu=1420

# Verify
hubble observe --from-pod default/frontend
# HTTP GET /large.bin 200 FORWARDED ✅
```

---

<!-- _class: divider -->

# 🏆 Phần 4
## So sánh & Decision Framework

---

<!-- _class: ep -->

# Tập 44
## So sánh 3 CNI: Flannel vs Calico vs Cilium — Bảng đánh giá toàn diện

`#kubernetes` `#CNI` `#comparison` `#flannel` `#calico` `#cilium`

---

## Tập 44 — Bảng So sánh 8 Tiêu chí

| Tiêu chí | Flannel | Calico | Cilium |
| :--- | :--- | :--- | :--- |
| **Dataplane** | iptables | iptables / eBPF | **eBPF thuần** |
| **NetworkPolicy** | ❌ Không | ✅ L3/L4 | ✅ **L3/L4/L7** |
| **BGP** | ❌ | ✅ BIRD | ✅ **GoBGP** |
| **Observability** | ❌ | Tự build | **Hubble built-in** |
| **Performance** | Trung bình | Tốt | **Tốt nhất** |
| **Độ phức tạp** | **Thấp** | Trung bình | Cao |
| **DNS Policy** | ❌ | ❌ | **✅ toFQDNs** |
| **L7 Policy** | ❌ | ❌ | **✅ HTTP/gRPC** |

---

## Tập 44 — Overhead so sánh

```
Packet cùng Node:

Flannel (VXLAN):    veth → bridge → VXLAN encap → VXLAN decap → bridge → veth
                    Overhead: ~50 bytes + full kernel stack

Calico (eBPF):      veth → eBPF TC hook → routing → eBPF TC hook → veth
                    Overhead: O(1) lookup, không encap nếu dùng BGP

Cilium (sockops):   socket ──────────────────────────────────► socket
                    Overhead: gần như 0 (bypass hoàn toàn)
```

**Latency benchmark (intra-node, p99):**
```
Flannel:  ~250 µs
Calico:   ~120 µs
Cilium:    ~35 µs  ← 7x nhanh hơn Flannel
```

---

<!-- _class: ep -->

# Tập 45
## Decision Framework: Khi nào dùng Flannel, Calico, Cilium trong Production?

`#kubernetes` `#CNI` `#production` `#architecture` `#decision`

---

## Tập 45 — Decision Flowchart

```
START: Bạn cần gì?
    │
    ├─ Dev/lab/học tập? Không cần NetworkPolicy?
    │   └──► FLANNEL ✅ Đơn giản, ít resource
    │
    ├─ Production? Cần NetworkPolicy?
    │   │
    │   ├─ Team quen BGP? Có ToR switch datacenter?
    │   │   └── Không cần L7 policy hay observability built-in?
    │   │       └──► CALICO ✅ Stable, BGP mature, iptables quen thuộc
    │   │
    │   └─ Cần ít nhất 1 trong các điều sau:
    │       ├── L7 policy (HTTP/gRPC method, path, DNS)
    │       ├── Observability không cần tự build
    │       ├── Performance cao nhất (high traffic cluster)
    │       └── Cluster lớn nhiều microservices
    │           └──► CILIUM ✅ Feature-rich, kernel eBPF
    │
    └─ Đang dùng managed K8s (EKS/GKE/AKS)?
        ├── EKS: AWS VPC CNI (mặc định) hoặc Cilium
        ├── GKE: Dataplane V2 = Cilium under the hood
        └── AKS: Azure CNI Powered by Cilium (GA)
```

---

## Tập 45 — Summary & Next Steps

**3 takeaways:**

1. **Flannel:** Bắt đầu nhanh, học CNI concepts — không dùng production nếu cần security
2. **Calico:** Solid cho production, BGP là thế mạnh, debug bằng iptables cần kinh nghiệm
3. **Cilium:** Future-proof, eBPF native, Hubble tiết kiệm nhiều giờ debug

**Roadmap tiếp theo từ kênh @NetworkThucChien:**
```
✅ Kubernetes Networking (series này)
🔜 Gateway API thực chiến — HTTPRoute, GRPCRoute, TCPRoute
🔜 Service Mesh so sánh — Istio vs Linkerd vs Cilium Service Mesh
🔜 eBPF từ đầu — viết eBPF program với libbpf/Go
```

> *"Hiểu mạng K8s từ kernel lên application — đó là kỹ năng phân biệt junior và senior."*

---

<!-- _class: title -->

# Cảm ơn đã theo dõi!

**@NetworkThucChien**

> Subscribe để không bỏ lỡ 45 tập thực chiến về Kubernetes Networking
