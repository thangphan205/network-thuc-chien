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

# Tập 20
## Lab 2: BGP không quảng bá Pod CIDR — Server vật lý không ping được Pod

**Phần 2 — Calico Labs** · `#BGP` `#lab` `#routing` `#BGPConfiguration`

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

1. **Simulate external server:** Dùng Multipass VM ngoài cluster làm monitoring server (Ubuntu 26.04).
2. **Reproduce:** Verify BGP UP nhưng monitoring server không reach Pod.
3. **Debug:** Phân tích bảng định tuyến trên monitoring server.
4. **Fix và verify:** Thêm Static Route trỏ qua ControlPlane IP, verify ping thành công.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

> **Tập tiếp theo:** Lab 3 — WireGuard MTU Black Hole, file nhỏ OK file lớn fail.
