# Lab Tập 5: Giải phẫu CNI - Hành trình cắm mạng thủ công

Từ trước đến nay, bạn vẫn thường nghe "Kubelet gọi CNI để cắm mạng cho Pod". Nhưng làm thế nào Kubelet "gọi" được CNI? Ngôn ngữ giao tiếp giữa chúng là gì? 

Bài Lab này sẽ chứng minh: **CNI không phải là một con daemon chạy ngầm**. Nó đơn thuần chỉ là các file thực thi (binary) vô tri vô giác. Hôm nay, BẠN sẽ đóng vai làm `Kubelet`, tự tay viết hợp đồng (JSON) và ép CNI phải cấp mạng cho bạn!

## 🛠 Yêu cầu chuẩn bị
- Không quan trọng cụm K8s đang sống hay chết. Bài Lab này hoàn toàn độc lập và chỉ thao tác ở mức hệ điều hành (OS).
- Toàn bộ thao tác dưới đây được thực hiện trên **Terminal đang SSH vào `worker1`**.

---

## 🚀 Thực nghiệm 1: Chuẩn bị "Đồ nghề" (cnitool)

Khi Kubelet gọi CNI, nó dùng code Golang bên trong mã nguồn K8s. Vì chúng ta đóng vai Kubelet, chúng ta sẽ dùng một công cụ thay thế tên là `cnitool` (được cung cấp bởi chính cha đẻ của chuẩn CNI).

1. Cài đặt môi trường Golang và tải `cnitool` về `worker1`:
   ```bash
   which go || (sudo apt-get update && sudo apt-get install -y golang-go)
   go install github.com/containernetworking/cni/cnitool@latest
   sudo cp ~/go/bin/cnitool /usr/local/bin/
   ```

2. Kiểm tra xem trên Node đã có sẵn các "tay sai" (plugin binaries) của CNI chưa:
   ```bash
   ls /opt/cni/bin/
   ```
   *Kết quả:* Bạn sẽ thấy hàng loạt các file binary như `bridge`, `host-local`, `loopback`, `flannel`... (Những file này được Kubeadm và Flannel tải về lúc dựng cụm). Đây chính là những kẻ sẽ trực tiếp làm nhiệm vụ cắm cáp!

---

## 📜 Thực nghiệm 2: Soạn thảo Hợp đồng CNI (.conflist)

Để gọi CNI, bạn phải tuân thủ chuẩn CNI Specification bằng cách truyền cho nó một chuỗi JSON mô tả mạng bạn muốn.

1. Tạo thư mục cấu hình và viết hợp đồng mạng có tên là `mynet`:
   ```bash
   sudo mkdir -p /etc/cni/net.d
   
   sudo tee /etc/cni/net.d/10-mynet.conflist << 'EOF'
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
           "gateway": "10.99.0.1",
           "routes": [
             { "dst": "0.0.0.0/0" }
           ]
         }
       },
       { "type": "loopback" }
     ]
   }
   EOF
   ```
   *Giải nghĩa:* Hợp đồng này yêu cầu CNI chạy qua 2 plugin:
   - Plugin 1 (`bridge`): Tạo một switch ảo tên `mybridge0`, dùng `host-local` để phát IP trong dải `10.99.0.10` -> `50`. Cài Default Gateway là `10.99.0.1`.
   - Plugin 2 (`loopback`): Bật card mạng `lo` lên.

---

## ⚡ Thực nghiệm 3: Đóng vai Kubelet gọi "Lệnh Bài" ADD

Bây giờ bạn sẽ tự tay mô phỏng quá trình Kubelet tạo Pod.

1. Tạo một "vùng đất trống" (Network Namespace) giống hệt cách Kubelet tạo Sandbox:
   ```bash
   sudo ip netns add cni-test
   ```

2. Ra lệnh cho `cnitool` thực thi hành động **ADD** vào Namespace vừa tạo:
   ```bash
   sudo CNI_PATH=/opt/cni/bin cnitool add mynet /var/run/netns/cni-test
   ```
   *Nhận xét:* `cnitool` sẽ đọc file `10-mynet.conflist` bạn vừa viết, tìm binary tương ứng trong thư mục `/opt/cni/bin` và truyền biến môi trường xuống. Kết quả in ra màn hình là một chuỗi JSON báo cáo *"Tôi đã cắm mạng xong, IP cấp là 10.99.0.10"*.

3. Kiểm chứng xem CNI có nói dối không bằng cách chui vào Namespace đó xem IP:
   ```bash
   sudo ip netns exec cni-test ip addr
   sudo ip netns exec cni-test ip route
   ```
   *Kết quả:* Thật vi diệu! Card `eth0` đã xuất hiện với IP `10.99.0.10` và có sẵn bảng định tuyến chỉa ra Gateway `10.99.0.1` đúng y như hợp đồng!

4. Kiểm tra switch ảo đã được tạo trên Node:
   ```bash
   ip link show mybridge0
   ```

5. Xem kho IPAM đã "khoá sổ" địa chỉ IP nào:
   ```bash
   sudo ls /var/lib/cni/networks/mynet/
   sudo cat /var/lib/cni/networks/mynet/10.99.0.10
   ```
   *Giải nghĩa:* Plugin `host-local` lưu trạng thái cấp phát IP vào thư mục này — mỗi IP đang dùng là một file riêng chứa Container ID. Đây là cơ chế giúp nó không cấp trùng IP.

---

## 🗑 Thực nghiệm 4: Thu hồi mạng bằng lệnh DEL

Khi Pod bị xóa, Kubelet sẽ phải dọn dẹp để không bị "rác" IP.

1. Ra lệnh cho `cnitool` thực thi hành động **DEL**:
   ```bash
   sudo CNI_PATH=/opt/cni/bin cnitool del mynet /var/run/netns/cni-test
   ```

2. Kiểm tra lại Namespace:
   ```bash
   sudo ip netns exec cni-test ip addr
   ```
   *Kết quả:* Card mạng `eth0` đã biến mất không để lại dấu vết.

3. Xác nhận IP đã được trả về kho IPAM:
   ```bash
   sudo ls /var/lib/cni/networks/mynet/
   ```
   *Kết quả:* File `10.99.0.10` đã biến mất — địa chỉ IP đã được giải phóng, sẵn sàng cấp cho Pod khác.

3. Dọn dẹp hoàn toàn hiện trường:
   ```bash
   sudo ip netns del cni-test
   sudo ip link del mybridge0 2>/dev/null || true
   ```

---

## ✅ Tổng kết

Bằng việc tự tay đóng vai Kubelet, bạn đã ngộ ra sự thật trần trụi về CNI:
1. **CNI là một cái Hợp Đồng (Specification)**: Quy định Kubelet phải ném vào input (JSON + ENV) như thế nào, và CNI plugin phải trả ra output (JSON) ra sao.
2. Quá trình cắm mạng/rút mạng là sự luân phiên gọi các hàm `ADD` và `DEL`.
3. Bạn hoàn toàn có thể tự build cụm mạng riêng cho các container bình thường của Linux mà không cần thiết phải cài nguyên một cụm Kubernetes đồ sộ!
