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

# Tập 5
## CNI là gì? Hành trình cắm mạng cho Pod từ ADD đến DEL

**Phần 0 — Nền tảng K8s Networking** · `#CNI` `#spec` `#cnitool` `#kubelet`

---

## Mục tiêu tập này

- Giải thích CNI spec là "hợp đồng" giữa kubelet và network plugin
- Vẽ luồng ADD/DEL/GC/STATUS đầy đủ
- Viết CNI config `.conflist` thủ công
- Gọi CNI plugin bằng `cnitool` mà không cần K8s

**Prerequisites:** Cluster từ Tập 1. Tập này có thể dùng VM standalone không cần cluster đầy đủ.

---

## CNI là hợp đồng, không phải code

```
CNI Specification v1.1.0 (2023)
─────────────────────────────────
kubelet nói: "Tao cần cắm mạng cho container này"
CNI plugin đáp: "OK, tao gán IP X.X.X.X và cài routes"

Hợp đồng gồm:
1. Plugin nhận config qua STDIN (JSON)
2. Plugin nhận environment variables (CNI_COMMAND, CNI_NETNS, ...)
3. Plugin trả kết quả qua STDOUT (JSON)
4. Plugin báo lỗi qua STDERR + exit code != 0
```

**4 động từ (verbs):**

| Verb | Khi nào | Tác dụng |
| :--- | :--- | :--- |
| `ADD` | Pod tạo mới | Cắm mạng, gán IP, cài routes |
| `DEL` | Pod xóa | Gỡ network, release IP về pool |
| `GC` | Periodic cleanup | Xóa stale network objects |
| `STATUS` | Health check | Kiểm tra plugin ready |

---

## Luồng ADD chi tiết

```
kubelet tạo container (PID của pause container)
    │
    ▼
Tạo network namespace: /var/run/netns/<id>
    │
    ▼
Đọc CNI config từ /etc/cni/net.d/ (theo thứ tự alphabetical)
    │
    ▼
Gọi plugin đầu tiên trong chain với:
  CNI_COMMAND=ADD
  CNI_NETNS=/var/run/netns/<id>
  CNI_CONTAINERID=<pause-container-id>
  CNI_IFNAME=eth0
  STDIN: { "cniVersion": "1.1.0", "name": "mynet", ... }
    │
    ▼
Plugin 1 (bridge): tạo cni0 bridge, tạo veth pair, gán IP
    │
    ▼
Plugin 2 (portmap): cài iptables rules cho port forwarding
    │
    ▼
Plugin 3 (firewall): cài iptables security rules
    │
    ▼
Trả STDOUT: { "ips": [{"address": "10.244.1.5/24"}], "routes": [...] }
    │
    ▼
kubelet lưu kết quả → Pod có IP ✅
```

---

## CNI conflist: Plugin chain

```json
{
  "cniVersion": "1.1.0",
  "name": "k8s-network",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.244.1.0/24",
        "routes": [{ "dst": "0.0.0.0/0" }]
      }
    },
    {
      "type": "portmap",
      "capabilities": { "portMappings": true }
    },
    {
      "type": "firewall",
      "backend": "iptables"
    }
  ]
}
```

---

<!-- _class: lab -->

## Lab Setup: Cài cnitool và CNI plugins

```bash
multipass shell k8s-worker1

# Cài CNI plugins binary (bridge, portmap, host-local, firewall...)
CNI_VERSION="v1.5.1"
mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | \
  sudo tar -C /opt/cni/bin -xz

ls /opt/cni/bin/
# bridge  firewall  host-local  ipvlan  loopback  macvlan  portmap  ...

# Cài cnitool
sudo apt-get install -y golang-go
go install github.com/containernetworking/cni/cnitool@latest
sudo cp ~/go/bin/cnitool /usr/local/bin/
```

---

## Lab: Gọi CNI ADD thủ công

```bash
# Tạo CNI config
sudo mkdir -p /etc/cni/net.d
cat | sudo tee /etc/cni/net.d/10-mynet.conflist << 'EOF'
{
  "cniVersion": "1.1.0",
  "name": "mynet",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "mybridge0",
      "isGateway": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.99.0.0/24",
        "rangeStart": "10.99.0.10",
        "rangeEnd": "10.99.0.50",
        "gateway": "10.99.0.1"
      }
    },
    { "type": "loopback" }
  ]
}
EOF

# Tạo network namespace để test
sudo ip netns add cni-test

# Gọi ADD — cắm mạng vào namespace cni-test
sudo CNI_PATH=/opt/cni/bin cnitool add mynet /var/run/netns/cni-test
# {
#   "cniVersion": "1.1.0",
#   "interfaces": [{"name": "mybridge0"}, {"name": "veth..."}],
#   "ips": [{"address": "10.99.0.10/24", "gateway": "10.99.0.1"}],
#   "routes": [{"dst": "0.0.0.0/0", "gw": "10.99.0.1"}]
# }

# Verify: xem mạng đã được cắm
sudo ip netns exec cni-test ip addr
# eth0: inet 10.99.0.10/24
sudo ip netns exec cni-test ip route
# default via 10.99.0.1 dev eth0
```

---

## Lab: Gọi CNI DEL và cleanup

```bash
# Xem bridge và veth đã tạo
ip link show mybridge0
ip link show type veth

# Gọi DEL — gỡ mạng và release IP
sudo CNI_PATH=/opt/cni/bin cnitool del mynet /var/run/netns/cni-test

# Verify: interface đã bị xóa
sudo ip netns exec cni-test ip addr
# (chỉ còn loopback)

# Gọi ADD lần 2 — IP có được tái sử dụng không?
sudo CNI_PATH=/opt/cni/bin cnitool add mynet /var/run/netns/cni-test
# "address": "10.99.0.10/24" ← Cùng IP được tái sử dụng!

# Cleanup hoàn toàn
sudo ip netns del cni-test
sudo ip link del mybridge0 2>/dev/null || true
```

---

## Vị trí CNI trong thực tế

```bash
# CNI config của Flannel (xem trên worker node)
ls /etc/cni/net.d/
# 10-flannel.conflist  ← Tên bắt đầu bằng số = thứ tự ưu tiên

cat /etc/cni/net.d/10-flannel.conflist
# {"cniVersion":"1.0.0", "name":"cbr0",
#  "plugins":[
#    {"type":"flannel","delegate":{"hairpinMode":true,"isDefaultGateway":true}},
#    {"type":"portmap","capabilities":{"portMappings":true}}
#  ]}

# CNI binaries Flannel cài
ls /opt/cni/bin/
# flannel  bridge  portmap  host-local ...

# Log của kubelet khi gọi CNI
sudo journalctl -u kubelet | grep -i "cni\|add\|del" | tail -20
```

---

## Key Takeaways

**CNI lifecycle:**
```
Pod create → kubelet → CNI ADD → IP assigned
Pod delete → kubelet → CNI DEL → IP released
Periodic   → kubelet → CNI GC  → stale cleanup
```

**Files quan trọng:**
```
/etc/cni/net.d/     ← Config (alphabetical, first wins)
/opt/cni/bin/       ← Binary plugins
/var/run/netns/     ← Network namespaces của containers
```

**Môi trường biến khi gọi CNI:**
```bash
CNI_COMMAND=ADD|DEL|GC|STATUS
CNI_NETNS=/var/run/netns/<id>
CNI_CONTAINERID=<container-id>
CNI_IFNAME=eth0
```

> **Phần tiếp theo (Tập 6):** Flannel — CNI đơn giản nhất giải bài toán flat network như thế nào?
