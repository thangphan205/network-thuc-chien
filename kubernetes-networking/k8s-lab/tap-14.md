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

# Tập 14
## veth pair & conntrack: Hành trình của 1 packet qua Calico

**Phần 2 — Calico** · `#packet-flow` `#veth` `#conntrack` `#iptables` `#trace`

---

## Mục tiêu tập này

- Vẽ đầy đủ hành trình packet từ Pod A → Pod B qua Calico
- Dùng iptables LOG để trace packet qua từng chain
- Quan sát conntrack table entries
- Hiểu tại sao conntrack quan trọng với NetworkPolicy

**Prerequisites:** Cluster Calico từ Tập 11-13 đang chạy iptables mode

---

## Hành trình packet: Cùng Node

```
Pod A (10.244.1.5)
    │ eth0 (trong Pod ns)
    ▼
vethXXX (root ns, nối vào cali bridge)
    │
    ▼
iptables FORWARD chain
    ├── cali-FORWARD
    │     └── cali-from-wl-dispatch → cali-fw-<Pod-A-id>
    │              ← Kiểm tra: Pod A có được gửi đi không?
    │              ← (egress policy của Pod A)
    ▼
Routing table: 10.244.1.6/32 via vethYYY (Pod B's veth)
    │
    ▼
iptables FORWARD chain lại
    └── cali-to-wl-dispatch → cali-tw-<Pod-B-id>
              ← Kiểm tra: ai được vào Pod B?
              ← (ingress policy của Pod B)
    │
    ▼
vethYYY → Pod B eth0 ✅
```

---

## Hành trình packet: Khác Node

```
Pod A (Node 1, 10.244.1.5) → Pod B (Node 2, 10.244.2.7)

Node 1:
  Pod A eth0 → vethXXX → iptables FORWARD
    → cali-fw-<Pod-A> (egress check) PASS
    → Routing: 10.244.2.0/24 via VXLAN/BGP
    → eth0 Node 1 → [network] → eth0 Node 2

Node 2:
  eth0 → iptables INPUT (hoặc FORWARD)
    → cali-to-wl-dispatch → cali-tw-<Pod-B> (ingress check) PASS
    → Route: 10.244.2.7/32 via vethYYY
    → vethYYY → Pod B eth0 ✅

Zero Trust: kiểm tra ở CẢ 2 đầu (egress Node 1 + ingress Node 2)
```

---

## conntrack: Biến stateless thành stateful

**Vấn đề:** TCP connection cần 2 chiều (request + response). Nếu chỉ allow ingress Pod B port 80, làm sao response từ Pod B đi ngược lại?

**conntrack giải quyết:**
```
Pod A → SYN → Pod B:80
  conntrack ghi: {10.244.1.5:random → 10.244.2.7:80} ESTABLISHED

Pod B → SYN-ACK → Pod A (ngược chiều)
  conntrack kiểm tra: "Có entry này không?"
  → Có! ESTABLISHED state → ALLOW (không cần rule riêng)

Kết quả: Chỉ cần 1 rule ALLOW ingress → response tự động được phép
```

---

<!-- _class: lab -->

## Lab Setup: Cài iptables LOG để trace

```bash
multipass shell k8s-worker1

# Switch Calico về iptables mode (nếu đang dùng eBPF)
kubectl patch felixconfiguration default \
  --type merge \
  --patch '{"spec":{"bpfEnabled":false}}'

# Tạo 2 Pods trên cùng worker1
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: trace-src
  labels: {app: src}
spec:
  nodeName: k8s-worker1
  containers:
  - {name: net, image: nicolaka/netshoot, command: ["sleep","infinity"]}
---
apiVersion: v1
kind: Pod
metadata:
  name: trace-dst
  labels: {app: dst}
spec:
  nodeName: k8s-worker1
  containers:
  - {name: net, image: nicolaka/netshoot, command: ["nc","-lk","-p","8080"]}
EOF

kubectl wait --for=condition=Ready pod/trace-src pod/trace-dst --timeout=60s
SRC_IP=$(kubectl get pod trace-src -o jsonpath='{.status.podIP}')
DST_IP=$(kubectl get pod trace-dst -o jsonpath='{.status.podIP}')
```

---

## Lab: Insert LOG rules và trace

```bash
# Thêm LOG rule trước cali-FORWARD để thấy mọi packet
sudo iptables -t filter -I FORWARD 1 \
  -j LOG --log-prefix "CALICO-TRACE: " --log-level 4

# Theo dõi kernel log
sudo dmesg -w | grep "CALICO-TRACE" &

# Gửi traffic từ trace-src đến trace-dst
kubectl exec trace-src -- nc -zv $DST_IP 8080

# Log sẽ hiện:
# CALICO-TRACE: IN=veth<src> OUT=veth<dst> SRC=10.244.1.X DST=10.244.1.Y
#               PROTO=TCP SPT=XXXXX DPT=8080 SYN

# Xem conntrack entry được tạo
sudo conntrack -L | grep $SRC_IP
# tcp   ESTABLISHED src=10.244.1.X dst=10.244.1.Y sport=XXXX dport=8080
#       [UNREPLIED]  src=10.244.1.Y dst=10.244.1.X sport=8080 dport=XXXX

# Cleanup LOG rule
sudo iptables -t filter -D FORWARD 1
```

---

## Lab: Quan sát DROP trong conntrack

```bash
# Apply policy chặn tất cả
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-trace-dst
spec:
  podSelector:
    matchLabels:
      app: dst
  policyTypes: [Ingress]
EOF

# Thêm LOG để thấy DROP
sudo iptables -t filter -I cali-FORWARD 1 \
  -j LOG --log-prefix "CALICO-DROP: "

# Thử kết nối — sẽ bị DROP
kubectl exec trace-src -- nc -zv $DST_IP 8080  # Timeout

# Log sẽ hiện: CALICO-DROP: ... DPT=8080 ...
# Và conntrack KHÔNG tạo ESTABLISHED entry vì không có response
sudo conntrack -L | grep $DST_IP
# (trạng thái SYN_SENT nhưng không chuyển sang ESTABLISHED)

# Cleanup
kubectl delete networkpolicy deny-trace-dst
sudo iptables -t filter -D cali-FORWARD 1
```

---

## Key Takeaways

**Calico chain order (iptables mode):**
```
INPUT/FORWARD → cali-FORWARD
                  ├── cali-from-wl-dispatch (egress check, Pod nguồn)
                  └── cali-to-wl-dispatch   (ingress check, Pod đích)
                        └── cali-tw-<id> → ACCEPT hoặc DROP
```

**conntrack là bạn của NetworkPolicy:**
```
Chỉ cần allow ingress port 80
conntrack tự động allow response từ port 80 về
```

**Debug tools:**
```bash
sudo iptables -t filter -L cali-FORWARD -n --line-numbers  # Xem rules
sudo conntrack -L | grep <ip>                               # Connection state
sudo iptables -t filter -I cali-FORWARD 1 -j LOG            # Trace (temp)
```

> **Tập tiếp theo:** NetworkPolicy cơ bản — Default Deny và viết Ingress Policy đúng cách.
