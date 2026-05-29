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
  section.warn { background: linear-gradient(135deg, #1a0800 0%, #0d1021 100%); }
  section.warn h2 { color: #f87171; border-bottom-color: #f87171; }
---

<!-- _class: ep -->

# Tập 8 - Flannel - host-gw
## Flannel host-gw: Định tuyến Trực tiếp & So sánh Hiệu năng

**Phần 1 — Flannel** · `#host-gw` `#underlay` `#routing` `#iperf3`
![height:200px](https://github.com/flannel-io/flannel/blob/master/logos/flannel-horizontal-color.png?raw=true)

---

## Mục tiêu tập này

- Tìm hiểu cơ chế định tuyến trực tiếp **host-gw** (Underlay) thay thế VXLAN (Overlay).
- Chuyển đổi backend, xử lý interface `flannel.1` tồn đọng sau khi switch mode.
- So sánh hiệu năng thực tế host-gw vs VXLAN bằng iperf3, hiểu điều kiện L2 boundary bắt buộc.

---

## host-gw: Định tuyến Underlay trực tiếp

**VXLAN mode (Overlay):**
```
Pod A → cni0 → flannel.1 → [UDP 8472 wrap] → eth0 → [unwrap] → flannel.1 → cni0 → Pod B
         └── CPU đóng gói ────── overhead 50 bytes ───────── CPU giải gói ──┘
```

**host-gw mode (Underlay):**
```
Pod A → cni0 → eth0 ─────────────────────────► eth0 ──────────────── cni0 → Pod B
                 Không đóng/giải gói — Đạt full MTU vật lý 1500 bytes
```

**Nguyên lý (flanneld tự cấu hình routes trực tiếp):**
```
Routing table trên worker1:
  10.244.0.0/24 via 192.168.64.10 dev eth0  ← "controlplane là gateway trực tiếp"
  10.244.1.0/24 dev cni0                    ← local subnet
  10.244.2.0/24 via 192.168.64.12 dev eth0  ← "worker2 là gateway trực tiếp"
```

---

## So sánh Tổng kết: VXLAN vs host-gw

| Tiêu chí | VXLAN Mode (Overlay) | host-gw Mode (Underlay) |
| :--- | :--- | :--- |
| Encapsulation overhead | 50 bytes | **0 bytes** |
| MTU cho payload | 1450 bytes | **1500 bytes** |
| Yêu cầu topology | Bất kỳ (L3 network ok) | **Phải cùng L2 subnet** |
| CPU overhead | Có (đóng/giải gói) | **Không (định tuyến kernel)** |
| Latency | Baseline | **Giảm ~30%** |
| Throughput | Baseline | **Tăng 10 - 15%** |
| Cloud compatibility | ✅ Rất tương thích | ❌ Thường bị Cloud drop packet chéo |


---

<!-- _class: lab -->

## 🔬 Lab Time: Định tuyến host-gw & Troubleshooting

Thực hành theo thứ tự trong file `lab-guide.md`:

1. **TN1 — Switch VXLAN → host-gw:** Xem config hiện tại, patch ConfigMap backend `host-gw`, restart DaemonSet.
2. **TN2 — Kiểm tra routing & dọn dẹp:** Xóa `flannel.1` cũ tồn đọng (`ip link delete flannel.1`), xem routing table trực tiếp qua `eth0`, verify MTU bridge tăng lên `1500`.
3. **TN3 — Benchmark iperf3:** Deploy iperf3 server/client cross-node, so sánh throughput với baseline VXLAN từ Tập 7.

👉 **Hãy làm theo các bước chi tiết trong file `lab-guide.md`**

---

## Key Takeaways

- **host-gw** định tuyến L3 trực tiếp, không bọc gói — MTU về 1500, throughput tăng ~10-15%.
- **Điều kiện bắt buộc**: tất cả Node phải cùng L2 segment. Cloud thường chặn packet có "foreign IP" → dùng VXLAN thay thế.
- **flannel.1 tồn đọng**: flanneld không tự xóa VTEP cũ khi switch mode — phải dọn thủ công `ip link delete flannel.1`.

> **Chương tiếp theo (Tập 9):** Calico CNI — Cài đặt từ đầu, giải quyết triệt để bài toán Lateral Movement và thực thi NetworkPolicy thực sự.
