# ⚡ iPerf3 — Benchmark băng thông mạng chuẩn mực

`iPerf3` là công cụ đo lường hiệu năng mạng tiêu chuẩn trong ngành. Không đoán mò "mạng chậm" — đo số cụ thể: throughput, jitter, packet loss, CPU usage khi truyền dữ liệu.

> **Lưu ý:** iPerf3 (phiên bản 3) không tương thích ngược với iPerf2. Phân biệt qua lệnh: `iperf3` vs `iperf`.

---

## ⚙️ Mô hình hoạt động

iPerf3 hoạt động theo mô hình **Client - Server**. Phải có 2 đầu:

```
Máy Server (listen)          Máy Client (khởi tạo test)
  iperf3 -s           ←→         iperf3 -c server_ip

  Port mặc định: 5201 (TCP)
```

Dữ liệu được gửi từ **Client → Server** (mặc định). Có thể đảo chiều với `--reverse`.

---

## 📖 Cheatsheet

### Setup Server
```bash
# Chạy server (lắng nghe port 5201)
iperf3 -s

# Chạy server trên port khác
iperf3 -s -p 9999

# Chạy server cho phép nhiều kết nối liên tiếp (daemon mode)
iperf3 -s -D
```

### Test TCP cơ bản
```bash
# Từ client: test 10 giây (mặc định)
iperf3 -c server_ip

# Chỉ định thời gian test
iperf3 -c server_ip -t 30    # Test 30 giây

# Kết quả dạng JSON (dùng trong script/automation)
iperf3 -c server_ip --json | jq '.end.sum_received.bits_per_second / 1e6'
```

### Test TCP nâng cao
```bash
# Multiple parallel streams (đo tổng throughput, bypass single-flow bottleneck)
iperf3 -c server_ip -P 4     # 4 luồng song song

# Đảo chiều — đo download từ server về client
iperf3 -c server_ip --reverse
# -R: throughput server → client thay vì client → server

# Test bi-directional (cả 2 chiều cùng lúc) — iPerf3 3.7+
iperf3 -c server_ip --bidir

# Giới hạn bandwidth (test QoS / rate limiting)
iperf3 -c server_ip -b 100M   # Chỉ gửi tối đa 100 Mbps
```

### Test UDP — Đo Jitter và Packet Loss
```bash
# UDP test (quan trọng cho VoIP, video streaming, gaming)
iperf3 -c server_ip -u -b 10M   # UDP với target 10 Mbps

# Lưu ý: PHẢI chỉ định -b khi dùng UDP
# Không có -b → flood UDP không giới hạn → congestion

# UDP với nhiều luồng
iperf3 -c server_ip -u -b 50M -P 4
```

### Cấu hình nâng cao
```bash
# Thay đổi kích thước buffer (ảnh hưởng TCP throughput)
iperf3 -c server_ip -w 4M     # Window size 4MB (tăng cho WAN latency cao)

# Đặt DSCP/TOS (test QoS marking)
iperf3 -c server_ip -S 0x10   # DSCP AF11

# Zero-copy mode (giảm CPU overhead)
iperf3 -c server_ip -Z

# Kết nối qua IPv6
iperf3 -c server_ipv6 -6
```

---

## 🔍 Đọc kết quả

### TCP output:
```
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  112 MBytes   940 Mbits/sec    0    374 KBytes
[  5]   1.00-2.00   sec  112 MBytes   940 Mbits/sec    0    374 KBytes
...
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  1.09 GBytes   938 Mbits/sec    0             sender
[  5]   0.00-10.00  sec  1.09 GBytes   937 Mbits/sec                  receiver
```

| Cột | Ý nghĩa |
| :--- | :--- |
| `Bitrate` | Throughput thực tế (Mbits/sec) |
| `Retr` | Số lần TCP retransmit — `> 0` = có packet loss hoặc congestion |
| `Cwnd` | TCP Congestion Window — càng lớn càng tốt, nếu nhỏ = bottleneck |

### UDP output:
```
[ ID] Interval     Transfer  Bitrate    Jitter    Lost/Total  Datagrams
[  5] 0.00-10.00s  12.5 MB   10.5 Mb/s  0.245 ms  0/8929 (0%)
```

| Cột | Ý nghĩa |
| :--- | :--- |
| `Jitter` | Dao động độ trễ (ms) — VoIP cần < 30ms |
| `Lost/Total` | Gói bị mất / tổng gói — `> 1%` = vấn đề nghiêm trọng |

---

## 📊 Kịch bản thực chiến

### "Đo throughput thực tế giữa 2 CNI trong K8s"
```bash
# Deploy iperf3 server Pod
kubectl run iperf3-server --image=networkstatic/iperf3 -- iperf3 -s

# Lấy IP của server Pod
SERVER_IP=$(kubectl get pod iperf3-server -o jsonpath='{.status.podIP}')

# Chạy client từ Pod khác (khác Node để test cross-node)
kubectl run iperf3-client --image=networkstatic/iperf3 --rm -it \
  -- iperf3 -c $SERVER_IP -t 30 -P 4
```

### "Tại sao throughput thấp hơn lý thuyết dù bandwidth đủ?"
```bash
# Test với nhiều luồng — single TCP flow bị giới hạn bởi RTT và window size
iperf3 -c server -P 1    # Single stream: 500 Mbps?
iperf3 -c server -P 8    # 8 streams: 950 Mbps ← đây mới là capacity thực

# Nếu 1 stream thấp → TCP window size bị giới hạn
# Throughput lý thuyết = Window Size / RTT
# Ví dụ: Window 64KB / 20ms RTT = 25 Mbps tối đa
iperf3 -c server -w 4M   # Tăng window size để bypass giới hạn này
```

### "Verify QoS / bandwidth shaping đang hoạt động"
```bash
# Test không giới hạn
iperf3 -c server -t 10   # Kết quả: 950 Mbps

# Test có giới hạn (simulate QoS)
iperf3 -c server -b 100M -t 10   # Target 100 Mbps
# Nếu kết quả = ~100 Mbps → rate limiting đang hoạt động
# Nếu kết quả = 950 Mbps → rate limiting bị bypass hoặc sai config
```

### "Debug VPN throughput thấp"
```bash
# Test ngoài VPN (baseline)
iperf3 -c public_server -t 30   # 500 Mbps

# Test qua VPN
iperf3 -c vpn_server -t 30      # 200 Mbps

# Nguyên nhân thường gặp:
# 1. CPU bottleneck: iperf3 -c vpn_server --json | jq '.end.cpu_utilization_percent'
# 2. MTU fragmentation: ping -s 1472 -M do vpn_server
# 3. Cipher overhead: thử đổi cipher (ChaCha20 vs AES-GCM)
```

---

## ⚠️ Lưu ý quan trọng

| Lưu ý | Chi tiết |
| :--- | :--- |
| **Firewall** | Mở port 5201 TCP/UDP trên server trước khi test |
| **UDP flood** | Luôn đặt `-b` khi test UDP, không để unlimited |
| **CPU limit** | iPerf3 single-threaded — throughput > 10 Gbps cần nhiều instance |
| **Test thời điểm** | Kết quả thay đổi theo giờ cao điểm — test nhiều lần |
| **Production** | Không chạy flood test trên network production |

---

> **Tóm lại:** `iperf3 -s` trên server, `iperf3 -c server_ip -P 4 -t 30` từ client. `-P 4` (parallel streams) cho kết quả thực tế hơn single stream. `Retr > 0` trong TCP = có congestion. `Jitter + Loss` trong UDP = chất lượng VoIP/gaming.
