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
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 43
## Cilium LB IPAM + Egress Gateway — On-prem LoadBalancer & Fixed Egress IP

**Phần 3 — Cilium** · `#loadbalancer` `#egress` `#on-prem` `#ipam` `#l2announcement`

---

## Vấn đề On-Prem: 2 Pain Points phổ biến nhất

```
Pain Point 1: LoadBalancer Service → EXTERNAL-IP <pending> mãi mãi

  kubectl expose --type=LoadBalancer → chờ... chờ... <pending>
  
  Lý do: LoadBalancer cần cloud provider hook (AWS ELB, GCP LB)
  On-prem/bare-metal: không có hook → EXTERNAL-IP không bao giờ xuất hiện
  
  Old solution: Cài MetalLB (thêm operator, config phức tạp)
  Cilium solution: Built-in LB IPAM + L2 Announcement

Pain Point 2: Traffic ra ngoài dùng IP ngẫu nhiên

  Pod restart → IP mới → Firewall rule phải update
  Pod scale → nhiều pods → nhiều IPs → firewall không thể whitelist
  
  Old solution: Sidecar proxy với fixed IP, hoặc dedicated NAT gateway
  Cilium solution: Egress Gateway
```

---

## Cilium LB IPAM: Cơ chế

```
Không có Cilium:
  Service type=LoadBalancer → EXTERNAL-IP: <pending> (mãi mãi)

Với Cilium LB IPAM:

  1. CiliumLoadBalancerIPPool định nghĩa IP pool:
     cidr: 192.168.64.200/29  (8 IPs)
  
  2. Cilium Operator detect LoadBalancer Service mới
     → Allocate IP từ pool (e.g. 192.168.64.200)
     → Patch Service.spec.externalIP
  
  3. CiliumL2AnnouncementPolicy:
     → Worker nodes compete để "own" IP (leader election)
     → Leader node reply ARP for 192.168.64.200
     → Host machine: ARP cache → traffic đến đúng node
  
  4. Failover:
     → Leader fail → lease expire (3s)
     → New leader elected → ARP updated
     → Downtime: < 3s (leaseDuration)
```

---

## L2 Announcement: Leader Election

```
Scenario: 192.168.64.200 cần được "owned" bởi 1 node

Normal:          worker1 "owns" 192.168.64.200
  Host → ARP → "Who has 192.168.64.200?"
  worker1 → ARP Reply → "Me! (00:11:22:33:44:55)"

worker1 fail:
  T+0s:  worker1 không renew lease
  T+3s:  Lease expires (leaseDuration = 3s)
  T+3s:  worker2 acquires lease
  T+3s:  worker2 → Gratuitous ARP → "192.168.64.200 is now at me!"
  T+3s:  Host ARP cache updated → traffic flows to worker2

Helm values:
  --set l2announcements.leaseDuration=3s      # failover time
  --set l2announcements.leaseRenewDeadline=1s # how often leader renews
  --set l2announcements.leaseRetryPeriod=200ms
```

---

## Egress Gateway: Stable Source IP

```
Vấn đề: Pod IP thay đổi → firewall rule bất ổn

Default behavior (không có Egress Gateway):
  Pod (10.244.1.x) → SNAT to node IP (random) → External Server
  Pod restart → new IP → new node → different SNAT IP

Với CiliumEgressGatewayPolicy:
  
  namespace: payment → ALL traffic → worker2 (egress gateway)
  worker2 SNAT source = worker2.IP (192.168.64.z) ← STABLE
  
  Pod restart → vẫn SNAT qua worker2 ← source IP không đổi
  Pod scale → tất cả pods dùng worker2 ← firewall rule: 1 IP

Production use cases:
  ✅ Firewall whitelist theo IP
  ✅ PCI-DSS: all payment traffic through specific node
  ✅ Compliance: egress audit từ known IP
  ✅ 3rd party API với IP-based auth
```

---

## CRDs mới trong Tập 43

```yaml
# 1. IP Pool cho LoadBalancer
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
spec:
  blocks:
  - cidr: "192.168.64.200/29"

# 2. L2 Announcement Policy
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
spec:
  nodeSelector: ...
  interfaces: ["^eth[0-9]+"]
  loadBalancerIPs: true

# 3. Egress Gateway Policy
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
spec:
  selectors:
  - podSelector:
      matchLabels:
        io.kubernetes.pod.namespace: payment
  destinationCIDRs: ["0.0.0.0/0"]
  egressGateway:
    nodeSelector:
      matchLabels:
        role: egress-gateway
    egressIP: 192.168.64.z  # worker2 IP
```

---

## So sánh: Cilium LB IPAM vs MetalLB

| Feature | MetalLB | Cilium LB IPAM |
| :--- | :--- | :--- |
| **Separate install** | ✅ Cần cài riêng | ❌ Built-in Cilium |
| **L2 mode** | ✅ | ✅ |
| **BGP mode** | ✅ | ✅ (Tập 46) |
| **Leader election** | Speaker pods | Cilium agent |
| **Config CRD** | IPAddressPool | CiliumLoadBalancerIPPool |
| **Integration** | Standalone | Native Cilium (Hubble visible) |
| **Failover time** | ~5-10s | ~leaseDuration (3s) |

> **Recommendation 2026:** Mới deploy → Cilium LB IPAM. Đã có MetalLB → không cần migrate.

---

<!-- _class: lab -->

## 🔬 Lab Time: LB IPAM + Egress Gateway

1. **Upgrade Cilium** với l2announcements + egressGateway enabled
2. **LB IPAM:** Tạo pool, deploy Service type=LoadBalancer, verify EXTERNAL-IP
3. **L2 Announcement:** Test failover khi drain worker node
4. **Egress Gateway:** Designate worker2 làm gateway, verify fixed source IP

👉 **Xem chi tiết trong `lab-guide.md`**

> **Tập tiếp theo (Tập 44):** Gateway API — north-south traffic routing với Cilium Ingress
