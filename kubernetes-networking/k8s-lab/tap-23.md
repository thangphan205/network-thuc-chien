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
  pre .hljs-comment, pre .hljs-meta { color: #7dd3fc; }
  pre .hljs-keyword, pre .hljs-selector-tag { color: #f9a8d4; }
  pre .hljs-string, pre .hljs-attr { color: #86efac; }
  pre .hljs-number, pre .hljs-literal { color: #fde68a; }
  pre .hljs-variable, pre .hljs-template-variable { color: #c4b5fd; }
  pre .hljs-built_in, pre .hljs-name { color: #67e8f9; }
  pre .hljs-subst { color: #e2e8f0; }
  section.ep { background: linear-gradient(135deg, #0d1021 0%, #12103a 100%); display: flex; flex-direction: column; justify-content: center; align-items: flex-start; padding: 60px 80px; }
  section.ep h1 { font-size: 1.8em; border: none; }
  section.ep h2 { border: none; color: #34d399; font-size: 1.1em; }
  section.lab { background: linear-gradient(135deg, #0a1a0a 0%, #0d1021 100%); }
---

<!-- _class: ep -->

# Tập 23
## Lab 2: BGP không quảng bá Pod CIDR — Server vật lý không ping được Pod

**Phần 2 — Calico Labs** · `#BGP` `#lab` `#routing` `#BGPConfiguration`

---

## Tình huống thực tế

```
DevOps team báo:
"Chúng tôi cần monitoring server (bare-metal, ngoài cluster)
 có thể scrape metrics trực tiếp từ Pod IP.
 BGP đang UP nhưng server không ping được Pod.
 Cluster đang dùng Calico BGP mode."

Thông tin:
- Monitoring server IP: 192.168.64.100 (VM ngoài cluster)
- BGP session: UP (calicoctl node status = ESTABLISHED)
- ping từ server: 100% packet loss
- Không có iptables firewall trên server
```

---

## Lab Setup: Simulate monitoring server

```bash
# Tạo thêm 1 VM Multipass simulate "monitoring server"
multipass launch 26.04 --name monitoring-server \
  --cpus 1 --memory 1G --disk 10G

MONITOR_IP=$(multipass info monitoring-server | grep IPv4 | awk '{print $2}')
echo "Monitoring server IP: $MONITOR_IP"

# Verify: monitoring-server không reach Pod IP hiện tại
POD_IP=$(kubectl get pod server -o jsonpath='{.status.podIP}')
multipass exec monitoring-server -- ping -c 3 $POD_IP
# 3 packets transmitted, 0 received ← Không reach được
```

---

## Debug bước 1: Verify BGP session

```bash
multipass shell k8s-master

# BGP session UP nhưng routing không work — kiểm tra route
calicoctl node status
# IPv4 BGP status
# PEER ADDRESS  STATE       INFO
# 192.168.64.11 up          Established BGP  ← UP
# 192.168.64.12 up          Established BGP  ← UP

# BGP UP nhưng routing không work → kiểm tra what's being advertised
# Dùng birdc để xem BGP route table (BIRD CLI)
multipass exec k8s-worker1 -- sudo birdc show route
# 10.244.1.0/26  via ... on eth0  ← Route của pod subnet ✅
# 10.244.2.0/26  via ... on eth0  ← Route đến worker2 ✅
# (Không có route đến monitoring-server)
```

---

## Debug bước 2: Routing table trên monitoring server

```bash
multipass exec monitoring-server -- ip route show
# default via 192.168.64.1 dev eth0
# 192.168.64.0/24 dev eth0

# Không có route đến 10.244.0.0/16!
# Tại sao? BGP không quảng bá Pod CIDR đến bên ngoài cluster

# Kiểm tra BGPConfiguration
calicoctl get bgpconfiguration default -o yaml
# spec:
#   asNumber: 64512
#   nodeToNodeMeshEnabled: true
#   serviceClusterIPs: []       ← TRỐNG! Không khai báo Pod CIDR export
#   # serviceExternalIPs: []    ← Cũng không có
```

---

## Fix: Khai báo Pod CIDR trong BGPConfiguration

```bash
# Fix: Thêm Pod CIDR vào serviceClusterIPs
# (Sẽ được quảng bá ra ngoài qua BGP)
calicoctl patch bgpconfiguration default \
  --patch '{
    "spec": {
      "serviceClusterIPs": [
        {"cidr": "10.244.0.0/16"}
      ]
    }
  }'

# Verify config
calicoctl get bgpconfiguration default -o yaml | grep -A3 serviceClusterIPs
# serviceClusterIPs:
# - cidr: 10.244.0.0/16   ✅

# Chờ BGP propagate (~5-10 giây)
sleep 10
```

---

## Verify và Test

```bash
# Verify route xuất hiện trên monitoring-server
# (Cần peer monitoring-server với BGP hoặc dùng static route để test)

# Cách đơn giản nhất: thêm static route vào monitoring-server
MASTER_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
multipass exec monitoring-server -- sudo ip route add 10.244.0.0/16 via $MASTER_IP

# Test ping từ monitoring-server đến Pod IP
POD_IP=$(kubectl get pod server -o jsonpath='{.status.podIP}')
multipass exec monitoring-server -- ping -c 5 $POD_IP
# 5 packets transmitted, 5 received  ✅ (Giờ reach được Pod trực tiếp!)

# Scrape metrics trực tiếp
multipass exec monitoring-server -- curl http://$POD_IP:8080/metrics
# (hoặc bất kỳ endpoint nào Pod expose)
```

---

## Key Lessons

**Root Cause:**
```
BGP session ESTABLISHED (control plane OK)
nhưng BGPConfiguration không khai báo Pod CIDR
→ BIRD không quảng bá 10.244.0.0/16 ra ngoài
→ External server không có route đến Pod IPs
→ Traffic không reach được
```

**Lesson: Control plane ≠ Data plane**
```
BGP "UP" chỉ nghĩa là: hai BGP peers đang nói chuyện
Không đảm bảo: Routing information đang được quảng bá đúng
Phải verify: actual routes trong routing table của destination
```

**Debug flow:**
```
BGP UP → Route table trên destination
→ BGPConfiguration serviceClusterIPs
→ birdc show route (BIRD routing table)
→ ip route show (kernel routing table)
```

> **Tập tiếp theo:** Lab 3 — WireGuard MTU Black Hole, file nhỏ OK file lớn fail.
