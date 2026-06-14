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

# Tập 45
## Cilium BGP Control Plane — Advertise Pod CIDRs và LoadBalancer IPs

**Phần 3 — Cilium** · `#bgp` `#gobgp` `#on-prem` `#routing` `#loadbalancer`

---

## L2 vs BGP: Khi nào dùng cái nào?

```
L2 Announcement (Tập 42):
  ✅ Tất cả nodes cùng broadcast domain (cùng VLAN)
  ✅ Multipass lab, bare-metal single-rack
  ✅ Đơn giản, không cần router config
  ❌ Không work nếu nodes ở different subnets
  ❌ Không scale tốt với nhiều VLANs
  ❌ ARP flooding với cluster lớn

BGP (Tập 45):
  ✅ Nodes ở different subnets/racks/datacenters
  ✅ Integration với existing datacenter routing
  ✅ ECMP load balancing across multiple nodes
  ✅ Route filtering, communities, policy
  ✅ Production datacenter standard
  ❌ Cần router/switch hỗ trợ BGP (FRR, Arista, Juniper)
  ❌ Phức tạp hơn để configure

Production rule of thumb:
  Single rack homelab → L2 Announcement
  Multi-rack datacenter → BGP
```

---

## Cilium BGP vs Calico BGP

| Feature | Calico (BIRD) | Cilium (GoBGP) |
| :--- | :--- | :--- |
| **BGP daemon** | BIRD (separate process) | GoBGP (built into agent) |
| **Config** | BGPPeer CRD + BGPConfiguration | CiliumBGPClusterConfig |
| **Maturity** | ★★★★★ (10+ years) | ★★★★☆ (2021+) |
| **Advertise pod CIDRs** | ✅ | ✅ |
| **Advertise LB IPs** | ✅ | ✅ |
| **BFD (fast failover)** | ✅ | Roadmap |
| **Route reflector** | ✅ | ✅ |
| **Integration** | Calico only | Native Cilium |

> Calico BGP mature hơn cho enterprise on-prem. Cilium BGP đang catch up nhanh.

---

## BGP Control Plane: CRD Structure

```yaml
# 1. Cluster-level BGP config
kind: CiliumBGPClusterConfig
spec:
  nodeSelector: {}         # Apply to all nodes
  bgpInstances:
  - name: "instance-65001"
    localASN: 65001        # Cluster ASN
    peers:
    - name: "tor-switch"
      peerASN: 65000       # ToR switch ASN
      peerAddress: "10.0.0.1"
      peerConfigRef:
        name: peer-config

# 2. Peer behavior config
kind: CiliumBGPPeerConfig
spec:
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 120

# 3. What to advertise
kind: CiliumBGPAdvertisement
spec:
  advertisements:
  - advertisementType: PodCIDR      # Pod subnets
  - advertisementType: Service      # LB IPs
    service.addresses: [LoadBalancerIP]
```

---

## BGP Advertisement Flow

```
Cluster deployment:
  cilium-agent discovers pod CIDR: 10.244.1.0/24 (worker1)
  cilium-agent BGP speaker: "I have route to 10.244.1.0/24 via 192.168.64.y"
  
BGP UPDATE sent to ToR switch:
  UPDATE: NLRI 10.244.1.0/24, NEXT_HOP 192.168.64.y, AS_PATH 65001

ToR switch routing table:
  10.244.0.0/24 via 192.168.64.x  (controlplane)
  10.244.1.0/24 via 192.168.64.y  (worker1)
  10.244.2.0/24 via 192.168.64.z  (worker2)

External client: curl 10.244.1.5
  → ToR: route 10.244.1.0/24 → 192.168.64.y (worker1)
  → worker1: BPF delivers to pod 10.244.1.5
  → No NAT, no tunnel, direct IP routing ✅

LB IP Advertisement:
  Service IP: 192.168.64.210 (LoadBalancer)
  Cilium advertises: 192.168.64.210/32 from ALL nodes (ECMP!)
  Router ECMP: hash(src_ip, dst_ip) → node selection
  → Horizontal scaling without additional LB
```

---

## Graceful Restart: Zero-Downtime Agent Updates

```
Without graceful restart:
  Agent restarts → BGP session drops
  Router: removes all routes from this peer
  Traffic blackhole for ~30-60s (route reconvergence)
  
With graceful restart (restartTimeSeconds: 120):
  Agent restarts → BGP session drops
  Router: "my peer supports graceful restart"
  Router: marks routes as STALE (not deleted!)
  Router: starts restart timer (120s)
  
  Agent recovers in ~20s:
    New BGP session established
    Agent sends fresh routes
    Router: removes stale flag
    
  Traffic: unaffected during those 20s ✅
  (stale routes forwarded correctly by router)

Production value:
  Agent upgrade, OOM, crash → traffic unaffected
  Requirement: restartTimeSeconds > agent recovery time
```

---

<!-- _class: lab -->

## 🔬 Lab Time: BGP Control Plane

1. **Enable** `bgpControlPlane.enabled=true` trong Helm
2. **Deploy FRR** container như BGP peer (ASN 65000)
3. **Configure** CiliumBGPClusterConfig (ASN 65001) + CiliumBGPPeerConfig
4. **Verify** sessions: `cilium bgp peers` → Established
5. **Advertise** pod CIDRs: xem routes trên FRR
6. **Advertise** LB IPs: verify /32 route trên FRR
7. **Graceful restart:** Kill agent, verify routes stay on FRR

👉 **Xem chi tiết trong `lab-guide.md`**

> **Tập tiếp theo (Tập 46):** BPF Map Sizing — tuning trước khi hit limits
