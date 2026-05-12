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
  section.final { background: linear-gradient(135deg, #1a0a2e 0%, #0d1021 50%, #0a1a2e 100%); }
---

<!-- _class: ep -->

# Tập 45
## Decision Framework: Khi nào dùng Flannel, Calico, Cilium trong Production?

**Phần 4 — Kết** · `#decision` `#framework` `#production` `#CNI` `#architecture`

---

## Mục tiêu tập này

- Flowchart quyết định CNI trong 5 câu hỏi
- Migration path: từ Flannel → Calico → Cilium
- Real-world scenarios: startup, enterprise, fintech
- Checklist trước khi production deploy

---

## Decision Flowchart: 5 câu hỏi

```
Câu 1: Bạn có cần NetworkPolicy không?
  NO  → Flannel (simplest, lowest overhead)
  YES → Tiếp tục...

Câu 2: Bạn có cần L7 HTTP/DNS policy không?
  YES → Cilium (duy nhất support tốt L7)
  NO  → Tiếp tục...

Câu 3: Cluster > 500 nodes hoặc > 1000 policies?
  YES → Cilium (iptables scale limit)
  NO  → Tiếp tục...

Câu 4: Team có BGP expertise và on-prem routers?
  YES → Calico (mature BGP, BIRD)
  NO  → Tiếp tục...

Câu 5: Observability là priority?
  YES → Cilium (Hubble built-in)
  NO  → Calico (lighter, simpler)
```

---

## Scenario 1: Startup — "Move fast, ship features"

```
Context:
  - 10 developers, 20 microservices
  - EKS cluster, 10-50 nodes
  - Security important nhưng không có dedicated security team
  - Observability cần để debug production issues

Answer: Cilium

Why:
  ✅ Hubble = instant network visibility cho small team
  ✅ L7 policy khi cần (không cần refactor sau này)
  ✅ EKS supports Cilium natively
  ✅ "Easy to debug" quan trọng hơn "easy to configure"

Setup: 
  EKS với Cilium CNI + Hubble enabled
  Không cần BGP (AWS managed networking)
  Hubble UI cho team visibility
```

---

## Scenario 2: Enterprise — "We run on-prem VMware"

```
Context:
  - 200+ nodes, hybrid cloud (VMware + AWS)
  - BGP peering với ToR switches
  - Security team cần compliance audit trail
  - Conservative org: prefer battle-tested solutions

Answer: Calico

Why:
  ✅ Calico BGP integration = best in class (BIRD)
  ✅ Most mature on-prem integration
  ✅ Large community, widely deployed
  ✅ Compliance tooling (Calico Enterprise)
  ✅ Conservative team = familiar tooling

Caveat:
  ⚠️  Setup Prometheus + Grafana manually cho observability
  ⚠️  Debug với calicoctl + iptables (slower)
```

---

## Scenario 3: Fintech — "Zero-trust, compliance, performance"

```
Context:
  - 1000+ nodes, regulated industry (PCI-DSS)
  - Must have: mTLS, L7 policy audit, egress control
  - Performance: payment API latency-sensitive
  - Full observability for compliance audit

Answer: Cilium (+ optionally Cilium Service Mesh)

Why:
  ✅ toFQDNs = control external payment API calls
  ✅ L7 policy = audit log every HTTP call
  ✅ Hubble Metrics = compliance reporting
  ✅ sockops = lower latency for payment flows
  ✅ WireGuard encryption = in-transit security

Optional:
  Cilium Service Mesh cho mTLS between services
  (instead of Istio, lower overhead)
```

---

## Scenario 4: Learning / Homelab

```
Context:
  - 1-3 nodes Multipass VMs
  - Learning K8s networking concepts
  - Budget: free tools only

Answer: Flannel → Then Calico → Then Cilium (progression)

Learning path:
  Week 1: Flannel
    kubectl apply -f kube-flannel.yml
    See pod-to-pod connectivity
    Understand VXLAN basics

  Week 2-4: Calico
    Understand NetworkPolicy
    Practice BGP concepts
    Debug with calicoctl

  Month 2+: Cilium
    L7 policy
    Hubble debugging
    BPF Maps exploration

This course: exactly this progression!
```

---

## Migration Path: Flannel → Calico → Cilium

```
Flannel → Calico:
  1. Deploy Calico alongside Flannel (không downtime!)
     → Calico manages new Pods
     → Flannel manages old Pods
  2. Rolling restart của all Pods
  3. Remove Flannel
  ⚠️  Risk: Dual-CNI transition window

Calico → Cilium:
  Option A: Full migration (downtime)
    1. Drain all Pods
    2. Remove Calico
    3. Install Cilium
    4. Redeploy
    
  Option B: Blue-green (no downtime)
    1. New node group với Cilium
    2. Migrate workloads
    3. Decommission Calico nodes

  Note: Không có in-place CNI swap không downtime!
  Plan maintenance window!
```

---

## Production Deployment Checklist

```bash
# Pre-deploy checklist cho bất kỳ CNI nào:

# 1. MTU planning
ip link show eth0 | grep mtu
# VXLAN: -50 bytes, WireGuard: -80 bytes
# Set CNI MTU = node MTU - overhead

# 2. CIDR không conflict với node/service CIDR
kubectl cluster-info dump | grep -E "cluster-cidr|service-cidr"
# Đảm bảo Pod CIDR, Service CIDR, Node CIDR không overlap

# 3. Kernel version compatible
uname -r
# Calico eBPF: Linux >= 5.4
# Cilium: Linux >= 5.10 recommended

# 4. NetworkPolicy default deny (nếu dùng Calico/Cilium)
kubectl apply -f default-deny-all-namespaces.yaml

# 5. Test connectivity sau deploy
kubectl apply -f cilium-connectivity-test.yaml
# Hoặc: kubectl -n kube-system exec cilium-xxx -- cilium connectivity test
```

---

## Final Recommendations: 2026 perspective

```
Cho cluster MỚI:
  → Cilium (trừ khi có reason cụ thể chọn khác)
  → Ecosystem đang hội tụ về eBPF
  → Managed K8s: all support Cilium

Cho cluster ĐANG CHẠY Calico:
  → Không cần migrate nếu không có pain point
  → Migrate khi: cần L7 policy, cần Hubble, scale issues

Cho cluster ĐANG CHẠY Flannel:
  → Migrate ngay nếu production (cần NetworkPolicy!)
  → Calico nếu on-prem BGP
  → Cilium nếu cloud-native

Skills đầu tư:
  Cilium + Hubble = most valuable 2026-2027
  eBPF fundamentals = differentiated skill
  BGP basics = always useful on-prem
```

---

<!-- _class: final -->

## Kết thúc khóa học

**45 tập — Kubernetes Networking từ A đến Z:**

```
Phần 0: K8s Networking Fundamentals (Tập 1-5)
  → Nền tảng không thể thiếu

Phần 1: Flannel (Tập 6-10)
  → Understand encapsulation basics

Phần 2: Calico (Tập 11-26)
  → Networking + Security production-ready

Phần 3: Cilium (Tập 27-43)
  → eBPF, L7 policy, Hubble observability

Phần 4: So sánh & Framework (Tập 44-45)
  → Make informed decisions
```

> **Cảm ơn đã theo dõi @NetworkThucChien!**
> Kubernetes networking không còn là "black box" nữa.

---

## Tiếp theo sau khóa học

```
Deep dive options:
  Service Mesh: Istio, Linkerd, Cilium Mesh
  eBPF Programming: libbpf, bcc, bpftrace
  K8s Advanced: Gateway API, Multi-cluster networking
  Security: Falco, OPA Gatekeeper, SPIFFE/SPIRE

Thực hành:
  CKA/CKAD certification
  Build your own CNI (học từ code)
  Contribute to Cilium open source

Community:
  Cilium Slack: cilium.io/slack
  Calico Slack: calicousers.slack.com
  K8s SIG-Network: kubernetes.io/community
```
