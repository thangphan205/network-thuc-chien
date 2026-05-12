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
<br />

# Series: Kubernetes Networking
## Thực chiến từ CNI đến NetworkPolicy

**Network Thực Chiến** · 45 Tập · 4 Phần · Flannel → Calico → Cilium
<br />

![height:200px](https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg)

---

## Cần chuẩn bị gì?

Series: Linux Networking - Network Thực Chiến
Series: Container Networking - Network Thực Chiến
Series: Debug Mạng Từ A-Z - Network Thực Chiến
Series: Học Kubernetes Tiếng Việt Full - Viet Tran
AI: Gemini, Claude, ChatGPT,...
Kiến thức cơ bản về k8s: Docs chính hãng


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
=> Mình dùng multipass
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
| 32–35 | Cilium NetworkPolicy: L3/L4, L7, DNS |
| 36–38 | Hubble: CLI, UI, Metrics |
| 39–43 | Troubleshooting + 4 Labs thực chiến |
| 44 | So sánh 3 CNI: Flannel vs Calico vs Cilium |
| 45 | Decision Framework: Khi nào dùng cái nào? |

