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

**Network Thực Chiến** · 42 Tập · 4 Phần · Flannel → Calico → Cilium

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

## Lộ trình 42 Tập

| Phần | Tập | Nội dung |
| :--- | :--- | :--- |
| **⚪ Phần 0** | 1–5 | Nền tảng K8s Networking |
| **🟡 Phần 1** | 6–10 | Flannel — Flat Network & VXLAN |
| **🔵 Phần 2** | 11–23 | Calico — NetworkPolicy, BGP, WireGuard |
| **🟣 Phần 3** | 24–40 | Cilium — eBPF, L7 Policy, Hubble |
| **🏆 Phần 4** | 41–42 | So sánh & Decision Framework |

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

## Phần 3–4: Cilium & Kết (Tập 24–45)

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

<!-- _class: ep -->

# Tập 16 - Calico - BGP
## BGP trong Calico: Node-to-Node Mesh và chuyển từ VXLAN

**Phần 2 — Calico** · `#BGP` `#AS` `#BIRD` `#routing` `#no-encapsulation`

![height:200px](https://www.tigera.io/app/uploads/2026/01/Calico-logo-2026-white-text.svg)

---

## Mục tiêu tập này

- Hiểu khi nào dùng BGP thay vì VXLAN/IPIP
- Cấu hình Calico sang BGP mode (không encapsulation)
- Dùng `calicoctl node status` để xem BGP session
- Verify: routing table thay đổi, tcpdump không còn VXLAN
- Troubleshoot 5 kịch bản BGP lỗi thường gặp trên môi trường thực

**Prerequisites:** Cluster Calico từ Tập 9-12 với VXLAN (sẽ chuyển sang BGP)

---

## BGP: Border Gateway Protocol

**Mỗi Node chạy BIRD daemon, quảng bá Pod CIDR của mình qua BGP sessions:**

```
Production — eBGP với ToR Switch:          Lab này — Node-to-Node Mesh (iBGP):

ToR Switch (AS 65000)                      controlplane (AS 64512)
    │                                           │
    ├── Node 1 (AS 64512)                  ────┼──── worker1 (AS 64512)
    │   Quảng bá: 10.244.1.0/26 ở đây         │     BGP session trực tiếp
    ├── Node 2 (AS 64512)                  ────┘──── worker2 (AS 64512)
    └── Node 3 (AS 64512)                        Full Mesh: n*(n-1)/2 sessions
```

**Lợi ích chung:**
- Không có encapsulation overhead (không VXLAN, không IPIP)
- Routes inject vào kernel với `proto bird` → forward thẳng qua `eth0`

---

## Hai topology BGP trong Calico

| | Node-to-Node Mesh | External BGP (với ToR) |
| :--- | :--- | :--- |
| **BGP type** | iBGP (cùng AS 64512) | eBGP (khác AS) |
| **Peer** | Mọi node peer với nhau | Mỗi node peer với ToR switch |
| **Scale** | n*(n-1)/2 sessions | n sessions (1 per node) |
| **Yêu cầu** | L2 flat network giữa nodes | L3 fabric + router hỗ trợ BGP |
| **Lab này** | ✅ | ❌ (Tập 17+) |

> **Lab này dùng Node-to-Node Mesh trên L2 flat network (Multipass).**
> Không cần ToR switch thật — BIRD trên mỗi node peer trực tiếp với nhau.

---

## Các chế độ mạng của Calico

| Chế độ | Encapsulation | Yêu cầu | Dùng khi |
| :--- | :--- | :--- | :--- |
| **VXLAN** | Full VXLAN | Bất kỳ topology | Cloud, multi-subnet |
| **IPIP** | IP-in-IP tunnel | L3 routed fabric | Datacenter |
| **BGP (direct)** | Không có | **L2 flat** (node mesh) hoặc L3 + BGP router | On-prem, performance |
| **VXLANCrossSubnet** | VXLAN chỉ khi cross-subnet | Mixed | Datacenter hybrid |

> **Điều kiện bắt buộc cho BGP direct:** tất cả nodes cùng L2 subnet.
> Nếu cross-subnet, packet bị router trung gian drop vì không biết route đến Pod CIDR.

---

## Khi nào dùng BGP

```
✅ On-premise datacenter với L3 fabric
✅ Cần server bare-metal access Pod IPs trực tiếp
✅ Performance-sensitive workloads
✅ Team đã quen BGP

❌ Cloud VPC (VPC routing không support custom pod CIDR)
❌ Simple cluster không cần routing integration
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Chuyển sang BGP mode và Verify

Chúng ta sẽ thực hành:

1. **Kiểm tra hệ thống:** Đảm bảo Nodes, Pods và Calico hoạt động bình thường.
2. **Switch sang BGP:** Patch IP Pool `ipipMode: Never` và `vxlanMode: Never`.
3. **Quan sát routing table:** Routes dùng `eth0` thay vì `vxlan.calico`, inject bởi BIRD.
4. **Xem BGP sessions:** `calicoctl node status` — verify `Established`.
5. **Test routing:** Tcpdump confirm không còn UDP 8472, ICMP đi thẳng.
6. **Troubleshoot:** 5 kịch bản lỗi thực tế — tạo lỗi → điều tra → fix.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## 🔧 Troubleshooting BGP — Tóm tắt

| Triệu chứng | Công cụ điều tra | Nguyên nhân phổ biến |
| :--- | :--- | :--- |
| BGP state `Active` | `nc -zv <peer> 179` | TCP 179 bị block (iptables) |
| BGP state `Idle` | `kubectl logs calico-node` | Felix chưa start |
| `proto bird` routes trống | `watch ip route show proto bird` | Felix chưa apply (đợi 30s) |
| Pod ping 100% loss, routes OK | `iptables -L FORWARD -n -v` | FORWARD chain DROP |
| `No process is using this socket` | `kubectl get pod -n kube-system` | calico-node pod restarting |
| `vxlan.calico` vẫn UP | `ip route show \| grep vxlan` | Transient — OK nếu routes dùng eth0 |

**Quy tắc debug:** Control plane OK (BGP up, routes có) → vấn đề ở dataplane (iptables). Routes trống → vấn đề ở Felix/BIRD.

---

## Bài toán Scale: Full Mesh BGP

**Full mesh = mỗi node peer với mọi node khác:**

```
n = số nodes    Số sessions = n × (n-1) / 2

3 nodes:    3 sessions    ✅  (lab hiện tại)
10 nodes:  45 sessions    ✅
50 nodes: 1225 sessions   ⚠️
100 nodes: 4950 sessions  ❌  mỗi node duy trì 99 TCP connections
500 nodes: 124750 sessions ❌❌
```

**Triệu chứng khi quá tải:** CPU spike trên calico-node, BGP convergence chậm, node mới join mất nhiều thời gian thiết lập sessions.

---

## Route Reflector: Giải pháp iBGP Scaling

**Thay vì peer full mesh, mỗi node chỉ peer với Route Reflector (RR):**

```
Full Mesh (6 nodes = 15 sessions):    Route Reflector (6 nodes = 6 sessions):

N1 ─── N2                             N1 ──┐
│ ╲   ╱ │                             N2 ──┤
│  N3   │          →                  N3 ──┼──► RR (controlplane)
│  │    │                             N4 ──┤
N4 ─── N5                             N5 ──┘
     N6
```

**Cách RR hoạt động:** RR nhận route từ client → reflect đến tất cả clients khác. NEXT_HOP giữ nguyên IP node gốc → packet forward trực tiếp node-to-node, không qua RR.

**Trade-off:** RR = single point of failure → production cần ≥ 2 RR nodes.

> Cấu hình thực hành RR có trong **Tập 17 (tài liệu tham khảo)**.

---

> **Tập tiếp theo:** WireGuard trong Calico — mã hóa traffic nội bộ giữa các nodes và bẫy MTU 1440 bytes.

---

<!-- _class: ep -->

# Tập 17 - Calico - WireGuard
## WireGuard trong Calico: Mã hóa traffic nội bộ & bẫy MTU 1440 bytes

**Phần 2 — Calico** · `#WireGuard` `#encryption` `#MTU` `#PMTUD` `#security`

<div style="display: flex; gap: 50px; justify-content: center; align-items: center; margin-top: 30px;">
  <img src="https://www.tigera.io/app/uploads/2026/01/Calico-logo-2026-white-text.svg" height="150" />
  <img src="https://www.wireguard.com/img/icons/og-logo.png?a=obiDa7ee" height="150" />
</div>

---

## Mục tiêu tập này

- Bật WireGuard encryption cho Pod-to-Pod traffic
- Tính toán MTU đúng với WireGuard overhead
- Reproduce PMTUD Black Hole và fix
- Hiểu khi nào cần WireGuard vs không cần

**Prerequisites:** Cluster Calico, Ubuntu 26.04 (Kernel 7.x+ có sẵn Wireguard module, cần cài `wireguard-tools` để debug)

---

## Tại sao cần WireGuard?

**Mặc định:** Pod-to-Pod traffic đi qua mạng nội bộ **không được mã hóa**.

```
Scenario nguy hiểm:
Node 1 → [Network switch] → Node 2
         Packet không mã hóa!

Nếu ai đó có thể sniff switch:
tcpdump -i eth0 → thấy toàn bộ Pod traffic
```

**WireGuard giải quyết:**
- Mã hóa toàn bộ Pod-to-Pod traffic (inter-node)
- Kernel-native (không cần userspace daemon)
- Modern crypto: Curve25519, ChaCha20, BLAKE2s
- Key rotation tự động

---

## WireGuard MTU Overhead

```
Physical MTU: 1500 bytes

WireGuard overhead (IPv4):
├── IP header:              20 bytes
├── UDP header:              8 bytes
├── WireGuard headers:      12 bytes (type, index, counter)
└── Auth tag (Poly1305):    16 bytes
                          ─────────
Total:                     60 bytes

Effective MTU: 1500 - 60 = 1440 bytes

Calico WireGuard default MTU: 1440 bytes
Port: UDP 51820
```

---

<!-- _class: warn -->

## PMTUD Black Hole — Bẫy MTU ẩn

```
TCP segment size > 1440 bytes + DF bit = 1 (Don't Fragment)
→ Router muốn fragment nhưng không được (DF=1)
→ Router DROP packet SILENTLY (không gửi ICMP fragmentation needed)
→ TCP sender không biết → không reduce MSS → hang mãi

Triệu chứng:
  Small files: OK (fit trong 1440 bytes)
  Large files: FAIL (hang, không báo lỗi rõ)
```

**Fix:**
```
1. Set wireguardMTU: 1440 (đúng overhead)
2. CNI tự đồng bộ MTU = 1440 xuống Pod interface
3. TCP stack trong Pod tự negotiate MSS ≤ 1400
```

---

## Khi nào cần WireGuard

```
✅ Multi-tenant cluster
✅ Compliance yêu cầu encryption in-transit
✅ Traffic qua untrusted network (multi-DC)
✅ Hybrid cloud

❌ Single-tenant, trusted private datacenter (overhead không đáng)
❌ Cluster với physical network security (isolation đã đảm bảo)
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Bật WireGuard và Fix MTU

Chúng ta sẽ thực hành:

1. **Kiểm tra WireGuard module:** Ubuntu 26.04 có sẵn trong kernel.
2. **Bật WireGuard:** Patch FelixConfiguration, verify `wireguard.cali` interface xuất hiện.
3. **Verify encryption:** Tcpdump thấy UDP 51820 với payload gibberish (encrypted).
4. **Reproduce PMTUD Black Hole:** Set MTU sai, file lớn hang, diagnose, fix.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## 🔧 Troubleshooting WireGuard & MTU — Tóm tắt

| Triệu chứng | Công cụ điều tra | Nguyên nhân & Cách xử lý |
| :--- | :--- | :--- |
| `wireguard.cali` không xuất hiện | `lsmod \| grep wireguard` | Kernel chưa load WireGuard module; chạy `modprobe wireguard` |
| Bật WireGuard nhưng traffic không mã hóa | `sudo wg show wireguard.cali` | `wireguardEnabled` chưa được set thành `true` trong FelixConfig |
| Gửi file lớn bị treo (PMTUD Black Hole) | `ping -s 1440 -M do <IP>` | MTU đặt quá cao (1500) khiến MSS tăng lên 1460; sửa `wireguardMTU: 1440` |
| Lỗi CNI khi pod khởi động | `kubectl describe pod` | Felix chưa cấu hình xong MTU; khởi động lại calico-node DaemonSet |

**Quy tắc debug:** Kiểm tra tầng Kernel (modprobe) → Kiểm tra config Calico (FelixConfig) → Kiểm tra Data Plane (iptables mangle & tcpdump UDP 51820).

---

> **Tập tiếp theo:** Troubleshooting Calico — workflow debug từ calicoctl đến ip route đến iptables.

---

<!-- _class: ep -->

# Tập 18
## Lab 1: Sự cố kết nối (Connection Timeout) không rõ nguyên nhân

**Phần 2 — Calico Labs** · `#lab` `#NetworkPolicy` `#troubleshooting`

---

## Mục tiêu tập này

- Debug production incident: frontend không gọi được backend mới
- Thực hành tự debug lỗi Connection Timeout
- Hiểu Felix event-driven: thêm label → rule cập nhật < 100ms
- Học checklist debug "connection timeout" trong Calico cluster

**Prerequisites:** Cluster Calico, namespace `production` có default-deny policy

---

## Tình huống thực tế

```
Thứ Hai, 9 giờ sáng. Developer gửi ticket:
"Tôi deploy backend mới. Frontend không gọi được backend.
 kubectl logs không có error. Không biết vấn đề ở đâu."

Thông tin:
- Cluster production đang chạy Calico
- Default deny đang active trong namespace
- Frontend → Backend qua Service port 8080
- curl từ frontend: timeout sau 30 giây
```

**Bạn là người xử lý — bắt đầu debug.**

---

## Root Cause (spoiler)

```
backend-v2 không có label app=backend
    ↓
NetworkPolicy podSelector: {app: backend} không match
    ↓
Felix không tạo allow rule cho backend-v2
    ↓
default-deny policy áp dụng (pod bị select vì podSelector: {})
    ↓
Frontend timeout khi kết nối
    ↓
kubectl logs không có error (problem ở network layer, không phải app)
```

**Lesson: Khi timeout không có error → nghi ngờ Network Policy ngay.**

---

## Felix Event-Driven Fix

```
Khi thêm label:

kubectl label pod backend-v2 app=backend
    ↓
K8s API nhận event → notify Felix
    ↓
Felix: "backend-v2 bây giờ match policy allow-frontend-to-backend"
    ↓
Felix atomic update iptables < 100ms
    ↓
Connection succeeded! (không cần restart Pod hay Node)
```

**Checklist debug "connection timeout":**
```bash
1. kubectl get pod --show-labels          # Labels đúng chưa?
2. kubectl get networkpolicy              # Policy nào đang active?
3. calicoctl get workloadendpoint         # Felix biết Pod không?
4. iptables -L cali-tw-<endpoint-id> -n  # Rule allow có tồn tại?
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Debug Label Typo Incident

Chúng ta sẽ thực hành:

1. **Setup incident:** Deploy backend-v2 (cấu hình deploy thực tế của developer), frontend có đủ labels.
2. **Reproduce symptom:** Frontend timeout khi gọi backend-v2.
3. **Thử thách 30 phút tự giải:** Học viên tự điều tra và tìm cách khắc phục lỗi.
4. **Hướng dẫn gỡ lỗi chuẩn:** Đối chiếu các bước troubleshooting chuẩn sau 30 phút.
5. **Fix và verify:** Khắc phục sự cố và kiểm tra kết nối thành công.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Tập 19 — Lab 2: BGP không quảng bá Pod CIDR

---

<!-- _class: ep -->

# Tập 19
## Lab 2: Sự cố kết nối từ Máy chủ ngoài vào cụm Kubernetes BGP

**Phần 2 — Calico Labs** · `#BGP` `#lab` `#routing` `#troubleshooting`

---

## Mục tiêu tập này

- Debug: BGP session UP nhưng external server không reach Pod
- Phân biệt "BGP UP" (control plane) vs "routes được quảng bá" (data plane)
- Hiểu cơ chế quảng bá BGP: BGP Peering thực tế vs Static Route trong lab
- Verify routing và kết nối từ external server đến Pod IP trực tiếp

**Prerequisites:** Cluster Calico đang chạy BGP mode (từ Tập 16), calicoctl đã cài

---

## Tình huống thực tế

```
DevOps team báo:
"Chúng tôi cần monitoring server (bare-metal, ngoài cluster)
 có thể scrape metrics trực tiếp từ Pod IP.
 BGP đang UP nhưng server không ping được Pod.
 Không có iptables firewall trên server."

Thông tin:
- BGP session: ESTABLISHED (calicoctl node status = up)
- ping từ monitoring server: 100% packet loss
- Cluster Calico BGP mode, không VXLAN
```

---

## Bẫy: "BGP UP" ≠ "Routes được quảng bá"

```
BGP session ESTABLISHED (control plane OK):
  Two peers đang nói chuyện: keepalive, open messages
  ← Đây chỉ là "BGP handshake thành công"

BGP routes được quảng bá (data plane):
  Peer A nói với Peer B: "10.244.1.0/26 ở tôi"
  Peer B cài route: 10.244.1.0/26 via <Peer-A-IP>
  ← Đây mới là "routing hoạt động"

Vấn đề: BGP UP không guarantee routes đang được advertise!
Phải verify: routing table trên destination có route đến Pod CIDR không?
```

**Tại sao external server không nhận được route?**
```
- BGP session chỉ chạy giữa các BGP Peer (các node K8s đã thiết lập mesh).
- External server chưa được cấu hình làm BGP Peer với cluster (không chạy BGP daemon).
- BIRD không thể tự động gửi thông tin định tuyến tới nó.
- (Pro Tip: spec.serviceClusterIPs chỉ dùng để quảng bá dải Service Cluster IP, không phải dải Pod)
```

---

## Giải pháp: BGP Peering vs Static Route

```
Production Design (Định tuyến động):
  - Cài đặt BGP daemon (FRR/BIRD) trên External Server.
  - Cấu hình Calico BGPPeer trỏ tới IP của Server.
  - Calico tự động đẩy route của Pod (IPPool) qua BGP.
  - Dùng serviceClusterIPs để quảng bá thêm dải Service Cluster IP.

Lab Solution (Định tuyến tĩnh - Static Route):
  - Do monitoring-server không chạy BGP daemon trong lab.
  - Thêm static route thủ công trên monitoring-server:
    sudo ip route add 10.244.0.0/16 via <ControlPlane-IP>
  - Đây là lab shortcut hoàn hảo & cực kỳ phổ biến trong thực tế (mô hình Hybrid).
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Debug BGP Route Advertisement

Chúng ta sẽ thực hành:

1. **Simulate external server:** Dùng Multipass VM ngoài cụm làm monitoring server.
2. **Reproduce:** Xác minh BGP UP nhưng monitoring server không reach Pod.
3. **Thử thách 30 phút tự giải:** Học viên tự tìm nguyên nhân và thiết lập định tuyến cho máy chủ ngoài.
4. **Hướng dẫn gỡ lỗi chuẩn:** Đối chiếu giải pháp động (BGP Peer) và tĩnh (Static Route).
5. **Fix và verify:** Cấu hình định tuyến tĩnh và kiểm tra ping thành công.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Tập 20 — Lab 3: WireGuard MTU Black Hole

---

<!-- _class: ep -->

# Tập 20
## Lab 3: Sự cố truyền nhận file dung lượng lớn qua WireGuard (MTU Black Hole)

**Phần 2 — Calico Labs** · `#WireGuard` `#MTU` `#PMTUD` `#troubleshooting`

---

## Mục tiêu tập này

- Reproduce PMTUD Black Hole với WireGuard MTU sai
- Chứng minh pattern: same-node OK, cross-node fail
- Debug: ping DF bit xác định MTU thực tế
- Fix: wireguardMTU đúng + MSS Clamping

**Prerequisites:** Cluster Calico, Ubuntu 26.04 (WireGuard kernel built-in)

---

## Tình huống thực tế

```
Ticket từ Backend team:
"Upload file ảnh < 1MB: OK.
 Upload file video > 5MB: hang mãi, không xong.
 Chỉ xảy ra khi upload qua Service vào Pod trên Node khác.
 Cùng Node thì OK.
 WireGuard đang bật trên cluster."

Dấu hiệu đặc trưng:
  ✓ "cross-node"
  ✓ "large file"
  ✓ "WireGuard bật"
  → Nghi ngờ PMTUD Black Hole ngay!
```

---

<!-- _class: warn -->

## PMTUD Black Hole — Cơ chế

```
MTU interface Pod = 1500 (sai, WireGuard cần 1440)
TCP packet lớn: 1450 bytes + DF bit = 1

Path:
  Pod A → [WireGuard] → 1450 + 60 bytes WG header = 1510
  Physical MTU = 1500 → 1510 > 1500 → muốn fragment
  DF = 1 → KHÔNG ĐƯỢC fragment
  Router SILENTLY DROP (không gửi ICMP fragmentation needed)

Kết quả:
  Sender không biết → tiếp tục gửi packet lớn
  → Connection hang mãi, không có error message
  
File nhỏ (< 1440 bytes): fit trong 1 packet → OK
File lớn (> 1440 bytes): bị drop → hang
```

---

## Debug Pattern

```bash
# 1. Cross-node vs same-node
# Same-node: không qua WireGuard tunnel → OK
# Cross-node: qua WireGuard tunnel → fail

# 2. Test với DF bit
ping -s 1440 -M do <cross-node-pod-ip>
# Nếu MTU sai → "message too long, mtu=1440"
# Kernel biết MTU thực = 1440 dù interface nói 1500

# 3. Fix MTU
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec":{"wireguardMTU":1440}}'

# 4. MSS Clamping thêm bảo vệ
# TCP stack tự negotiate MSS (hoặc set wireguardMssClamp nếu cần)
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Reproduce và Fix PMTUD Black Hole

Chúng ta sẽ thực hành:

1. **Setup incident:** Kích hoạt WireGuard mã hóa và cấu hình MTU mặc định.
2. **Reproduce:** File nhỏ OK, file lớn chéo node bị treo (hang) -> timeout.
3. **Thử thách 30 phút tự giải:** Học viên tự tìm nguyên nhân và khắc phục lỗi chéo node.
4. **Hướng dẫn gỡ lỗi chuẩn:** Đối chiếu các kỹ thuật chẩn đoán (ping DF bit) và xử lý MTU.
5. **Fix và verify:** Cấu hình MTU tối ưu, MSS Clamping và kiểm tra truyền file thành công.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Tập 21 — Lab 4: Cross-namespace policy bug

---

<!-- _class: ep -->

# Tập 21
## Lab 4: Sự cố phân quyền truy cập chéo Namespace (Logic AND vs OR)

**Phần 2 — Calico Labs** · `#lab` `#cross-namespace` `#prometheus` `#troubleshooting`

---

## Mục tiêu tập này

- Debug 2 bugs cùng lúc trong cross-namespace policy
- Hiểu cách Bug 2 (missing label) mask Bug 1 (OR vs AND)
- Chứng minh fix chỉ 1 bug có thể tạo security hole nghiêm trọng hơn
- Áp dụng checklist verification trước khi apply cross-namespace policy

**Prerequisites:** Cluster Calico, namespace `production` và `monitoring`

---

## Tình huống thực tế

```
Monitoring team báo:
"Prometheus trong namespace 'monitoring' không scrape được
 backend metrics endpoint (port 9090) trong namespace 'production'.
 Chúng tôi đã viết NetworkPolicy rồi nhưng vẫn timeout."

Thông tin:
- Namespace monitoring (label?)
- Prometheus Pod label: role=prometheus
- Backend Pod label: app=backend
- Policy đã apply nhưng không hoạt động
```

**Lab này: 2 bugs cùng lúc — phải fix cả 2 mới OK.**

---

<!-- _class: warn -->

## 2 Bugs cùng lúc — Nguy hiểm đặc biệt

```
Bug 1: OR thay vì AND (dấu "-" sai chỗ)
  → Policy quá rộng: bất kỳ Pod nào trong monitoring vào được
  → Security hole!

Bug 2: Namespace thiếu label
  → namespaceSelector không match → policy không hoạt động
  → Bug 2 mask Bug 1 (timeout → người dùng không thấy security hole)

Nếu chỉ fix Bug 2 (thêm label namespace):
  → Bug 1 trở thành security hole THỰC SỰ
  → Policy hoạt động nhưng quá rộng
  → Bất kỳ Pod nào trong monitoring đều vào được!
```

**Phải debug và fix CẢ HAI.**

---

## Logic Cú Pháp NetworkPolicy: AND vs OR

*Sự khác biệt cực kỳ nhỏ ở cú pháp dấu gạch ngang (`-`) tạo nên hậu quả bảo mật khổng lồ:*

### ❌ Cấu hình sai (OR Logic) - 2 dấu gạch ngang
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels: {name: monitoring}
  - podSelector:
      matchLabels: {role: prometheus}
```
> **Kết quả:** Cho phép *bất kỳ Pod nào* thuộc namespace `monitoring` **HOẶC** *bất kỳ Pod nào* có nhãn `role: prometheus` ở bất kỳ đâu trong cluster (bao gồm cả namespace `default`, `dev`...).

---

## Logic Cú Pháp NetworkPolicy: AND vs OR (tiếp)

###  Cấu hình đúng (AND Logic) - 1 dấu gạch ngang duy nhất
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels: {name: monitoring}
    podSelector:                  # <- Không có dấu "-" ở đây = AND!
      matchLabels: {role: prometheus}
```
> **Kết quả:** Chỉ cho phép Pod có nhãn `role: prometheus` **VÀ** phải nằm trong namespace `monitoring`. Đây là quy tắc bảo mật chặt chẽ nhất theo nguyên tắc đặc quyền tối thiểu.

---

<!-- _class: lab -->

## Pro Tip: Kubernetes Namespace Auto-Labeling

- Từ **Kubernetes v1.21+**, control plane tự động gắn nhãn mặc định `kubernetes.io/metadata.name: <namespace-name>` cho mọi Namespace khi khởi tạo.
- **Lợi ích:** Ta không còn lo quên gắn nhãn thủ công (tránh được hoàn toàn Bug 2).

### Cấu hình Modern & An Toàn:
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: monitoring  # Nhãn tự động của K8s
    podSelector:
      matchLabels:
        role: prometheus
```
*(Khuyên dùng cho các dự án thực tế để loại bỏ thao tác thủ công dễ sai sót).*

---

## Checklist trước khi apply cross-namespace policy

```bash
# 1. Verify namespace có label
kubectl get namespace <ns> --show-labels
# Expected: name=<ns> trong LABELS column

# 2. Đếm dấu "-" trong from block
# Mỗi "- " = 1 item = OR với items khác
# Cùng item = AND

# 3. Test với rogue pod (namespace đúng, label sai)
kubectl run rogue -n monitoring --image=nicolaka/netshoot -- sleep infinity
kubectl -n monitoring exec rogue -- nc -zv <backend-ip> 9090
# Expected: timeout (blocked)

# 4. Test với legit pod (namespace đúng, label đúng)
kubectl -n monitoring exec prometheus -- nc -zv <backend-ip> 9090
# Expected: success
```

---

<!-- _class: lab -->

## 🔬 Lab Time: Debug 2 Bugs Cùng Lúc

Chúng ta sẽ thực hành:

1. **Setup incident:** Deploy NetworkPolicy chéo namespace (cấu hình lỗi chéo namespace).
2. **Reproduce:** Xác minh Prometheus bị chặn kết nối (Connection Timeout) tới Backend.
3. **Thử thách 30 phút tự giải:** Học viên tự tìm nguyên nhân và khắc phục lỗi logic ẩn.
4. **Hướng dẫn gỡ lỗi chuẩn:** Đối chiếu các bước troubleshooting chuẩn để tìm ra 2 lỗi ẩn.
5. **Fix và verify:** Áp dụng logic AND chính xác, dán nhãn namespace và kiểm tra ma trận kết nối bảo mật.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Tập 22 — Tổng kết & Workflow Debug chuẩn trong Calico

---

<!-- _class: ep -->

# Tập 22
## Tổng kết & Workflow Troubleshooting Calico chuẩn

**Phần 2 — Calico** · `#troubleshooting` `#debug` `#methodology` `#calicoctl`

---

## Mục tiêu tập này

- Hệ thống hóa workflow debug Calico (không đoán mò) sau 4 bài Lab thực hành
- Đúc kết đủ bộ tool: calicoctl, ip route, iptables-save, tcpdump
- Tổng kết 4 sự cố mạng kinh điển: Label Typo, BGP Route Loss, WireGuard MTU Black Hole, Cross-Namespace Policy
- Phân biệt rạch ròi lúc nào check Control Plane vs Data Plane

**Prerequisites:** Đã hoàn thành 4 bài Lab thực hành từ Tập 18 đến Tập 21

---

## Workflow debug Calico — 5 bước chuẩn

```
Symptom: Pod A không kết nối được tới Pod B (Timeout/Refused)

Bước 1: CHECK BASICS
  kubectl get pods -o wide       # Pod đang chạy? Đúng Node?
  kubectl get endpoints          # Service có endpoints chưa?

Bước 2: CHECK ROUTING & BGP
  calicoctl node status          # BGP sessions UP/Established?
  ip route show proto bird       # Có route đến subnet của Pod B?

Bước 3: CHECK NETWORK POLICY
  kubectl get networkpolicy      # Có policy nào select Pod không?
  calicoctl get workloadep       # Felix đã nhận diện Pod endpoint?

Bước 4: CHECK LABELS & LOGIC
  kubectl get pod --show-labels  # Nhãn Pod có khớp selector (AND/OR)?

Bước 5: CHECK KERNEL DATA PATH & LOGS
  iptables-save | grep cali      # Rule có tồn tại trong iptables?
  tcpdump -i any host <pod-ip>   # Gói tin có thực sự đi đến card mạng?
```

---

## Control Plane vs Data Plane

```
Control Plane (Quản lý & Thiết lập):
  calicoctl node status       → BGP session state (BIRD)
  calicoctl get workloadep    → Felix Agent biết Pod không?
  kubectl get networkpolicy   → Policy cấu hình trong K8s API

Data Plane (Thực thi & Chuyển mạch):
  ip route show               → Route có nạp vào Linux Kernel?
  iptables -L cali-FORWARD    → Rule có trong Linux iptables/eBPF?
  conntrack -L | grep <ip>    → Bảng theo dõi trạng thái kết nối
  tcpdump -i any host <ip>    → Gói tin thực tế đi/đến đâu?

Bẫy kinh điển:
"BGP UP" ≠ "Routing OK" (Lab 2 - Tập 19)
"Policy applied" ≠ "iptables rule match" (Lab 1 - Tập 18, Lab 4 - Tập 21)
→ Phải kiểm tra song song cả hai tầng!
```

---

## Debug Command Toolkit Cheatsheet

```bash
# Control plane
calicoctl node status                        # BGP sessions
calicoctl get workloadendpoint               # Workload endpoints Felix nhận diện
calicoctl get networkpolicy --all-namespaces # Tất cả policies trong Calico

# Data plane
ip route show proto bird                     # Pod subnet routes học qua BGP
iptables-save | grep cali | wc -l            # Số lượng Calico rules trong Node
iptables -L cali-tw-<iface-id> -n            # Xem rule inbound vào Pod (tw = to-workload)
iptables -L cali-fw-<iface-id> -n            # Xem rule outbound từ Pod (fw = from-workload)
conntrack -L -p tcp | grep <pod-ip>          # Trạng thái connection

# Packet trace (TEMP, xóa sau khi debug)
iptables -I FORWARD 1 -j LOG --log-prefix "DBG: "
dmesg -w | grep DBG
```

---

<!-- _class: lab -->

## 🔬 Tổng hợp 4 Lab Scenarios đã thực hành

Chúng ta đã gỡ lỗi thành công 4 sự cố thực tế kinh điển:

1. **Lab 1 (Tập 18): Label Typo** -> Felix Event-Driven cập nhật iptables cực nhanh, timeout do drop âm thầm khi thiếu nhãn.
2. **Lab 2 (Tập 19): BGP Route Loss** -> BGP session giữa các Node UP nhưng máy chủ ngoài cluster không có route tĩnh/động để forward packet.
3. **Lab 3 (Tập 20): WireGuard MTU** -> Lớp mã hóa làm phình packet chéo Node, router drop âm thầm với cờ DF=1 (PMTUD Black Hole). Sửa bằng `wireguardMTU: 1440` & MSS Clamping.
4. **Lab 4 (Tập 21): Cross-Namespace Policy** -> Lỗi cú pháp dấu gạch ngang (AND vs OR logic) bị che giấu bởi lỗi thiếu nhãn Namespace (Bug Masking).

---

## ✅ Lời khuyên khi Troubleshoot mạng K8s

1. **Không đoán mò:** Luôn bám sát workflow 5 bước từ cơ bản đến nâng cao.
2. **Lỗi im lặng (Timeout) vs Lỗi từ chối (Refused):**
   - Timeout -> Packet bị DROP âm thầm (thường do NetworkPolicy/iptables).
   - Connection Refused -> Packet đến được đích nhưng không có app nào lắng nghe port (TCP RST).
3. **Luôn kiểm tra ma trận bảo mật:** Khi sửa NetworkPolicy, hãy chắc chắn kiểm tra cả client được phép (legit) và client trái phép (rogue/attacker).

---

> **Tập tiếp theo:** Tập 23 — Calico Observability: Giám sát mạng K8s với Prometheus & Grafana

---

<!-- _class: ep -->

# Tập 23
## Calico Observability: Prometheus + Grafana + AlertManager

**Phần 2 — Calico** · `#observability` `#prometheus` `#grafana` `#alertmanager` `#metrics`

---

## Mục tiêu tập này

- Bật Felix metrics endpoint trong Calico
- Deploy kube-prometheus-stack qua Helm
- Cấu hình ServiceMonitor để Prometheus scrape Felix
- Tạo PrometheusRule alerts cho BGP down và packet drop rate cao

**Prerequisites:** Cluster Calico đang chạy, Helm đã cài hoặc sẽ cài trong lab

---

## Felix Metrics — Những gì Calico expose

```bash
# Bật Felix metrics (port 9091 mặc định)
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec": {"prometheusMetricsEnabled": true}}'

# Scrape thủ công từ node
curl http://<node-ip>:9091/metrics | grep -E "^felix_|^bgp_" | head -10
```

**Metrics quan trọng nhất:**

| Metric | Ý nghĩa |
| :--- | :--- |
| `bgp_peers{status="Established"}` | BGP sessions đang UP |
| `felix_denied_packets_total` | Packets bị NetworkPolicy DROP |
| `felix_active_local_endpoints` | Pods active trên node này |
| `felix_iptables_restore_calls_total` | Tần suất iptables update |
| `felix_calc_graph_update_time_seconds` | Policy calculation time |

---

## Stack Observability Calico

```
Felix (port 9091) ──► Prometheus ──► Grafana Dashboards
                            │
                            └──► AlertManager ──► Email/Slack/PagerDuty

Cài đặt qua kube-prometheus-stack (Helm chart):
  - Prometheus Operator
  - Prometheus
  - Grafana (với Datasource tự động)
  - AlertManager
  - Node Exporter
  - kube-state-metrics
```

---

## ServiceMonitor — Cách Prometheus biết scrape gì

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: calico-felix
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames: [calico-system]
  selector:
    matchLabels:
      k8s-app: calico-node    # Service có label này
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
```

**Luồng:**
```
ServiceMonitor → Prometheus Operator đọc → Prometheus config update
→ Prometheus scrape Service → Pull metrics từ Felix
→ Metrics available trong Prometheus/Grafana
```

---

## Alert Rules quan trọng

```yaml
# BGP session down — critical
- alert: CalicoBGPSessionDown
  expr: bgp_peers{status="Established"} < 1
  for: 2m
  labels: {severity: critical}

# Packet drop rate cao — warning (possible misconfigured policy)
- alert: CalicoHighDeniedPackets
  expr: rate(felix_denied_packets_total[1m]) > 0.5
  for: 10s
  labels: {severity: warning}

# Không có active endpoints — warning
- alert: CalicoEndpointDrop
  expr: felix_active_local_endpoints < 1
  for: 5m
  labels: {severity: warning}
```

---

## 4 Dashboards cần có trong production

| Dashboard | Query PromQL | Alert khi |
| :--- | :--- | :--- |
| **BGP Status** | `bgp_peers{status="Established"}` | < 1 per node |
| **Deny Rate** | `rate(felix_denied_packets_total[1m])` | > 100/s |
| **Endpoint Count** | `felix_active_local_endpoints` | < 1 per node |
| **Policy Calc Time** | `felix_calc_graph_update_time_seconds` | p99 > 1s |

---

<!-- _class: lab -->

## 🔬 Lab Time: Deploy Observability Stack

Chúng ta sẽ thực hành:

1. **Bật Felix metrics:** Patch FelixConfiguration và verify port 9091.
2. **Deploy kube-prometheus-stack:** Helm install Prometheus + Grafana + AlertManager.
3. **Cấu hình ServiceMonitor:** Prometheus tự động scrape Felix.
4. **Tạo Alert rules:** PrometheusRule cho BGP và packet drop.
5. **Trigger alert:** Generate traffic bị deny và xem alert FIRING.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Phần tiếp theo (Tập 24):** Tại sao Cilium? Pain points của Calico và sockops bypass.

---

<!-- _class: divider -->

# 🟣 Phần 3
## Cilium — eBPF, L7 Policy & Hubble

---

<!-- _class: ep -->

# Tập 24
## Tại sao Cilium? Pain points của Calico & sockops bypass

`#cilium` `#eBPF` `#sockops` `#performance`

---

## Tập 24 — 3 Pain Points của Calico

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

# Tập 25
## BPF Maps: Hash, LRU, Array, Per-CPU — Vũ khí hiệu năng của Cilium

`#cilium` `#eBPF` `#BPFMaps` `#kernel` `#performance`

---

## Tập 25 — 4 Loại BPF Map

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

# Tập 26
## Kiến trúc Cilium: Operator, Agent, GoBGP, Hubble — So sánh với Calico

`#cilium` `#architecture` `#GoBGP` `#Hubble`

---

## Tập 26 — Cilium vs Calico Architecture

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

# Tập 27
## 3 Hook Points của eBPF: XDP, TC và sockops — Mỗi cái làm gì?

`#cilium` `#eBPF` `#XDP` `#TC` `#sockops`

---

## Tập 27 — eBPF Hook Points

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

# Tập 28
## Cùng Node vs Khác Node: Tại sao sockops bypass hoàn toàn XDP/TC?

`#cilium` `#sockops` `#performance` `#same-node` `#zero-trust`

---

## Tập 28 — Same Node vs Different Node

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

# Tập 29
## L3/L4 Policy trong Cilium: So sánh với Kubernetes NetworkPolicy

`#cilium` `#CiliumNetworkPolicy` `#L3` `#L4`

---

## Tập 29 — CiliumNetworkPolicy vs K8s NetworkPolicy

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

# Tập 30
## L7 Policy: Chặn HTTP POST theo path với Envoy Proxy

`#cilium` `#L7` `#HTTP` `#Envoy` `#NetworkPolicy`

---

## Tập 30 — L7 HTTP Policy

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

# Tập 31
## DNS Policy với toFQDNs: Filter theo domain thay vì IP — CDN multi-IP trap

`#cilium` `#DNS` `#toFQDNs` `#egress` `#CDN`

---

## Tập 31 — Vấn đề với IP-based egress policy

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

# Tập 32
## Cilium + Istio: Khi nào kết hợp, khi nào dùng Cilium thuần?

`#cilium` `#istio` `#servicemesh` `#mTLS` `#architecture`

---

## Tập 32 — Cilium thuần vs Cilium + Istio

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

# Tập 33
## Hubble CLI: `hubble observe` — Debug real-time không cần SSH vào Pod

`#cilium` `#hubble` `#CLI` `#observability` `#debug`

---

## Tập 33 — hubble observe

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

# Tập 34
## Hubble UI: Service Map tự động & DROPPED màu đỏ

`#cilium` `#hubble` `#UI` `#servicemap` `#visualization`

---

## Tập 34 — Hubble UI

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

# Tập 35
## Hubble Metrics: hubble_drop_total, http_requests — Đúng tool, đúng tình huống

`#cilium` `#hubble` `#metrics` `#prometheus` `#monitoring`

---

## Tập 35 — Hubble Metrics & Đúng Tool

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

# Tập 36
## Troubleshooting Cilium: cilium status → hubble observe → cilium CLI

`#cilium` `#troubleshooting` `#debug` `#methodology`

---

## Tập 36 — Workflow Debug Cilium

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

# Tập 37
## Lab 1: Pod label sai — Hubble show "Policy denied" ngay lập tức

`#cilium` `#lab` `#hubble` `#label` `#debug`

---

## Tập 37 — Lab 1: Label Bug với Hubble

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

# Tập 38
## Lab 2: L7 Policy thiếu HTTP method — HTTP 403 & quy trình confirm dev

`#cilium` `#L7` `#lab` `#HTTP403` `#process`

---

## Tập 38 — Lab 2: L7 403 Forbidden

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

# Tập 39
## Lab 3: DNS Egress Policy & toFQDNs trap — External API fail bí ẩn

`#cilium` `#DNS` `#toFQDNs` `#lab` `#egress`

---

## Tập 39 — Lab 3: DNS Egress Fail

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

# Tập 40
## Lab 4: WireGuard MTU với Cilium — Hubble show "MTU exceeded" ngay!

`#cilium` `#WireGuard` `#MTU` `#lab` `#hubble`

---

## Tập 40 — Lab 4: WireGuard MTU (Cilium vs Calico)

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

# Tập 41
## So sánh 3 CNI: Flannel vs Calico vs Cilium — Bảng đánh giá toàn diện

`#kubernetes` `#CNI` `#comparison` `#flannel` `#calico` `#cilium`

---

## Tập 41 — Bảng So sánh 8 Tiêu chí

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

## Tập 41 — Overhead so sánh

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

# Tập 42
## Decision Framework: Khi nào dùng Flannel, Calico, Cilium trong Production?

`#kubernetes` `#CNI` `#production` `#architecture` `#decision`

---

## Tập 42 — Decision Flowchart

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

## Tập 42 — Summary & Next Steps

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
