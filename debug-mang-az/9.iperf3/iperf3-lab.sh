#!/usr/bin/env bash

# ==============================================================================
# iPerf3 Practical Lab (PoC)
# Tự động tạo môi trường giả lập mạng (Network Namespaces) để thực hành iPerf3.
# Yêu cầu: Chạy trên Linux bằng quyền root (sudo) vì sử dụng 'ip netns' và 'tc'.
# ==============================================================================

set -e

# Đảm bảo chạy với quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script này bằng quyền root (sudo ./iperf3-lab.sh)"
  exit 1
fi

echo "====================================================="
echo "🔬 Bắt đầu thiết lập môi trường Lab iPerf3..."
echo "====================================================="

# 1. Dọn dẹp môi trường cũ (nếu có)
ip netns del iperf-srv 2>/dev/null || true
ip netns del iperf-cli 2>/dev/null || true

# 2. Tạo 2 Network Namespaces (Client & Server)
echo "[+] Tạo Network Namespaces (iperf-srv, iperf-cli)"
ip netns add iperf-srv
ip netns add iperf-cli

# 3. Tạo cặp veth pair (virtual ethernet) nối 2 namespace
echo "[+] Kết nối 2 Namespaces bằng veth pair"
ip link add veth-srv type veth peer name veth-cli
ip link set veth-srv netns iperf-srv
ip link set veth-cli netns iperf-cli

# 4. Gán IP và khởi động interfaces
echo "[+] Gán IP cho interfaces (Server: 10.0.0.1, Client: 10.0.0.2)"
ip netns exec iperf-srv ip addr add 10.0.0.1/24 dev veth-srv
ip netns exec iperf-srv ip link set veth-srv up
ip netns exec iperf-srv ip link set lo up

ip netns exec iperf-cli ip addr add 10.0.0.2/24 dev veth-cli
ip netns exec iperf-cli ip link set veth-cli up
ip netns exec iperf-cli ip link set lo up

# 5. Khởi động iPerf3 Server chạy ngầm trong namespace iperf-srv
echo "[+] Khởi động iPerf3 Server (chạy nền)"
ip netns exec iperf-srv iperf3 -s -D

echo ""
echo "✅ MÔI TRƯỜNG LAB ĐÃ SẴN SÀNG!"
echo "-----------------------------------------------------"
echo "Server IP : 10.0.0.1 (chạy ngầm iperf3 -s)"
echo "Client IP : 10.0.0.2"
echo "-----------------------------------------------------"

sleep 2

# ==============================================================================
# KỊCH BẢN 1: BASELINE (LÝ TƯỞNG)
# ==============================================================================
echo ""
echo "🚀 [KỊCH BẢN 1] Đo baseline throughput (Mạng local, không có limit)"
echo "Lệnh: ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 3 -O 1"
echo "Chạy bài test..."
ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 3 -O 1 | grep -E "sender|receiver|sec"

# ==============================================================================
# KỊCH BẢN 2: MÔ PHỎNG ĐƯỜNG TRUYỀN WAN (LATENCY 50ms)
# ==============================================================================
echo ""
echo "🚀 [KỊCH BẢN 2] Mô phỏng kết nối WAN (Thêm độ trễ 50ms)"
echo "[+] Áp dụng Traffic Control (tc) thêm latency 50ms vào Server..."
ip netns exec iperf-srv tc qdisc add dev veth-srv root netem delay 50ms

echo "[+] 2.A: Single Stream (Sẽ bị thắt cổ chai do TCP Window / RTT)"
echo "Lệnh: ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5"
ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5 | grep -E "sender|receiver"

echo ""
echo "[+] 2.B: Bật 4 luồng song song (-P 4) để vượt qua giới hạn"
echo "Lệnh: ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5 -P 4"
ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5 -P 4 | grep -E "SUM.*sender|SUM.*receiver"

# Xóa rule latency
ip netns exec iperf-srv tc qdisc del dev veth-srv root

# ==============================================================================
# KỊCH BẢN 3: MÔ PHỎNG MẠNG CHẬP CHỜN (PACKET LOSS 2%)
# ==============================================================================
echo ""
echo "🚀 [KỊCH BẢN 3] Mô phỏng Packet Loss 2% (Mạng kém)"
echo "[+] Áp dụng Traffic Control (tc) packet loss 2%..."
ip netns exec iperf-srv tc qdisc add dev veth-srv root netem loss 2%

echo "[+] 3.A: TCP Test qua đường truyền có loss (Để ý cột 'Retr')"
echo "Lệnh: ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5"
ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5 | grep -E "sec"

echo ""
echo "[+] 3.B: UDP Test qua đường truyền có loss (Để ý cột 'Lost/Total')"
echo "Lệnh: ip netns exec iperf-cli iperf3 -c 10.0.0.1 -u -b 10M -t 3"
ip netns exec iperf-cli iperf3 -c 10.0.0.1 -u -b 10M -t 3 | grep -E "sec.*%"

# Xóa rule packet loss
ip netns exec iperf-srv tc qdisc del dev veth-srv root

# ==============================================================================
# KỊCH BẢN 4: MÔ PHỎNG RATE LIMIT (QoS - 50Mbps)
# ==============================================================================
echo ""
echo "🚀 [KỊCH BẢN 4] Mô phỏng Rate Limiting (Giới hạn 50Mbps bằng Token Bucket Filter)"
echo "[+] Áp dụng Traffic Control (tc) limit 50mbit..."
ip netns exec iperf-srv tc qdisc add dev veth-srv root tbf rate 50mbit burst 32kbit latency 400ms

echo "[+] Test TCP với mạng bị giới hạn 50Mbps"
echo "Lệnh: ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5 -P 2"
ip netns exec iperf-cli iperf3 -c 10.0.0.1 -t 5 -P 2 | grep -E "SUM.*sender|SUM.*receiver"

# ==============================================================================
# KẾT THÚC VÀ DỌN DẸP
# ==============================================================================
echo ""
echo "====================================================="
echo "🧹 Đang dọn dẹp môi trường (xóa namespaces)..."
ip netns del iperf-srv
ip netns del iperf-cli
echo "✅ Hoàn tất bài Lab thực chiến iPerf3!"
echo "====================================================="
