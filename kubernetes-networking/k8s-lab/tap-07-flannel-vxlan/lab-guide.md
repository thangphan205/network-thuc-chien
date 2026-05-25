# Lab Tập 7: VXLAN Backend — Soi packet thực tế với tcpdump và Giải mã MTU

Tập này chúng ta sẽ dùng công cụ `tcpdump` để "soi" sâu vào bên trong đường hầm VXLAN tunnel, xác minh toàn bộ lý thuyết 50-byte overhead bằng thực nghiệm thực tế, và tìm hiểu cách hệ điều hành đàm phán kích thước gói tin nhằm tối ưu hóa đường truyền mạng.

---

## 🧭 Cấu trúc byte-by-byte của VXLAN Packet trên đường truyền

Khi gói tin đi trên dây cáp mạng vật lý (on the wire) giữa hai node, nó được bọc thành nhiều lớp L2/L3 lồng ghép cực kỳ chặt chẽ:

```
+---------------------------------------------------------------------------------------------------+
|                                      PHYSICAL ETHERNET FRAME                                      |
+----------------------+------------------+-----------------+---------------------------------------+
|  Outer Ethernet (L2) |  Outer IP (L3)   | Outer UDP (L4)  |            VXLAN HEADER               |
|      14 Bytes        |    20 Bytes      |    8 Bytes      |              8 Bytes                  |
| [Src Node MAC |      | [Src Node IP |    | [Src Port: Var  | [Flags (8b) | Reserved (24b) |        |
|  Dst Node MAC]       |  Dst Node IP]    |  Dst Port: 8472 |  VXLAN Network Identifier VNI (24b)   |
|                      |  Protocol: UDP   |  Length | Csum] |  Reserved (8b)]                       |
+----------------------+------------------+-----------------+---------------------------------------+
|                                  ENCAPSULATED INNER POD FRAME                                     |
+-----------------------------------------------------------+---------------------------------------+
|                    Inner Ethernet (L2)                    |             Inner IP (L3)             |
|                          14 Bytes                         |               20 Bytes                |
|               [Src Pod MAC | Dst Pod MAC]                 |       [Src Pod IP | Dst Pod IP]       |
+-----------------------------------------------------------+---------------------------------------+
|                       Inner L4 Header                     |                 PAYLOAD               |
|                    e.g. ICMP (8B) or TCP (20B)            |                 e.g. 64 Bytes         |
+-----------------------------------------------------------+---------------------------------------+
```

### 🧮 Công thức tính toán 50-byte Overhead:
* **Outer IP Header**: `20 bytes` (Định vị IP vật lý giữa Node nguồn và Node đích).
* **Outer UDP Header**: `8 bytes` (Chứa Source Port ngẫu nhiên để load-balancing và Destination Port cố định `8472`).
* **VXLAN Header**: `8 bytes` (Chứa trường VNI - VXLAN Network Identifier = 1 để định danh mạng).
* **Inner Ethernet**: `14 bytes` (Địa chỉ MAC ảo giữa Pod nguồn và VTEP đích).
* **Tổng cộng**: `20 + 8 + 8 + 14 = 50 bytes`.

---

## 🧭 Cơ chế Tự động Tối ưu hóa TCP MSS (Maximum Segment Size)

Bạn có thể tự hỏi: "Nếu MTU của Pod bị hạ xuống 1450, liệu ứng dụng có bị chậm đi do hệ điều hành phải liên tục chia cắt các packet lớn hay không?"

Câu trả lời là **Không**, nhờ vào cơ chế tự động đàm phán **TCP MSS**:
1. Khi một ứng dụng bên trong Pod thiết lập một kết nối TCP (ví dụ gửi một HTTP request), nó sẽ bắt đầu bằng quá trình bắt tay 3 bước (3-way handshake).
2. Khi gửi gói tin `SYN` khởi tạo, TCP stack trong nhân Linux của Pod sẽ kiểm tra MTU của interface ảo `eth0` (được gán mặc định là `1450`).
3. TCP stack sẽ tự động tính toán kích thước Payload tối đa cho một phân đoạn TCP, gọi là **MSS**:
   $$\text{TCP MSS} = \text{MTU} - \text{IP Header} (20\text{ bytes}) - \text{TCP Header} (20\text{ bytes}) = 1450 - 20 - 20 = 1410\text{ bytes}$$
4. Pod sẽ gửi thông số `MSS = 1410` này trong cờ SYN tới Server đích. Server nhận được thông số này và cam kết **chỉ** gửi các gói TCP có payload tối đa là `1410` bytes.
5. Khi gói tin này ra tới host và được VTEP bọc thêm `50` bytes VXLAN overhead, tổng kích thước gói tin vật lý sẽ là đúng:
   $$1410\text{ (Payload)} + 20\text{ (TCP)} + 20\text{ (Inner IP)} + 50\text{ (VXLAN Overhead)} = 1500\text{ bytes}$$
   Con số `1500` này khớp hoàn hảo với MTU chuẩn của hạ tầng vật lý, giúp gói tin đi qua các router trung gian trơn tru mà không bao giờ bị phân mảnh (fragmentation) ở mức vật lý!

---

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Flannel VXLAN đang chạy (Tập 6).
- `pod-a` trên `worker1`, `pod-b` trên `worker2` (nếu chưa có, tạo lại từ Tập 6).

---

## 🔬 Thí nghiệm 1: Verify cấu hình VTEP & Bắt VXLAN traffic với tcpdump

Thực hiện các bước bắt gói tin trên `worker1` bằng lệnh:
```bash
sudo tcpdump -i eth0 -n udp port 8472 -v
```
Và kích hoạt ping từ `pod-a` sang `pod-b` ở `controlplane`. Bạn sẽ thấy rõ 2 tầng IP (Inner và Outer) hiển thị trong log như tài liệu gốc.

---

## 🔬 Thí nghiệm 2: Chứng minh 50 bytes overhead bằng length field

Thực hiện theo các bước trong file lab gốc để đo chính xác chiều dài Outer IP packet (`length 134`) so với Inner IP packet (`length 84`), từ đó rút ra hiệu số đúng `50 bytes`.

---

## 🔬 Thí nghiệm 3: Đo MTU thực tế bằng DF bit (Don't Fragment)

Chạy thử nghiệm ping với size tối đa `-s 1422` và cờ cấm phân mảnh `-M do` để thấy rõ hệ điều hành chặn gói tin ngay lập tức khi kích thước vượt quá giới hạn MTU `1450`.

---

## 🔬 Thí nghiệm 4: Benchmark throughput ở VXLAN mode với iperf3

Sử dụng công cụ `iperf3` để chạy đo đạc throughput baseline ở chế độ mạng Overlay VXLAN giữa 2 Node vật lý ảo. Ghi lại kết quả để đối chiếu ở Tập 8.

---

## 💥 Thực hành Khắc phục Sự cố (Troubleshooting)

### 🔍 Sự cố 1: Sự cố "MTU Black Hole" (Ping gói tin nhỏ thì thông, kết nối HTTP/API lớn thì treo vĩnh viễn)
* **Triệu chứng**: Bạn đứng từ `pod-a` ping sang `pod-b` thấy phản hồi rất nhanh và thông suốt. Tuy nhiên, khi bạn thực hiện gọi API lớn, `curl` lấy file HTML hoặc gửi dữ liệu qua `gRPC`/`HTTP` thì kết nối bị treo cứng (hoặc báo `Connection timed out` sau một thời gian dài).
* **Nguyên nhân**: Cụm K8s của bạn chạy trên một hạ tầng ảo hóa (ví dụ chạy VM lồng nhau trong AWS/GCP, hoặc hạ tầng OpenStack doanh nghiệp) mà bản thân hạ tầng này đã dùng mạng Overlay sẵn. Do đó, MTU vật lý của card `eth0` trên Host của bạn không phải là `1500` mà chỉ là `1450` hoặc thấp hơn.
  Khi Flannel VXLAN mặc định cấu hình MTU cho Pod là `1450` (giả định MTU host là 1500), các packet ICMP nhỏ (~84 bytes) truyền bình thường. Nhưng khi gửi dữ liệu TCP lớn, packet đạt ngưỡng MTU `1450` bytes của Pod. Ra đến Host, VTEP bọc thêm 50 bytes thành `1500` bytes và phát ra card `eth0` (với MTU vật lý thực tế chỉ là `1450`). Do gói tin có cờ cấm phân mảnh **DF (Don't Fragment)**, Router vật lý sẽ âm thầm hủy gói tin đó (silent drop) mà không báo lại cho Pod. Đây gọi là hiện tượng **MTU Black Hole**.
* **Cách khắc phục**:
  1. Xác định MTU vật lý thực tế bằng cách ping cấm phân mảnh từ Host này sang Host khác:
     ```bash
     ping -s 1422 -M do <IP_WORKER2_VẬT_LÝ>
     ```
     Nếu bị lỗi `message too long`, hãy hạ nhỏ dần kích thước `-s` (ví dụ `1372`) cho đến khi ping thành công. MTU thực tế của Host = $\text{kích thước ping thành công} + 28\text{ bytes (IP/ICMP header)}$. Ví dụ ping thành công ở `1372` -> MTU Host thực tế là `1400`.
  2. Chúng ta phải cấu hình lại MTU của Flannel Pods sao cho: $\text{MTU Pod} = \text{MTU Host} - 50\text{ bytes} = 1400 - 50 = 1350\text{ bytes}$.
  3. Sửa ConfigMap `kube-flannel-cfg`:
     ```bash
     kubectl edit configmap kube-flannel-cfg -n kube-flannel
     ```
     Trong phần `net-conf.json`, bổ sung cấu hình MTU:
     ```json
     {
       "Network": "10.244.0.0/16",
       "Backend": {
         "Type": "vxlan",
         "MTU": 1350
       }
     }
     ```
  4. Khởi động lại DaemonSet Flannel:
     ```bash
     kubectl rollout restart ds kube-flannel-ds -n kube-flannel
     ```
  5. **⚠️ CỰC KỲ QUAN TRỌNG:** Bạn phải xóa và khởi động lại toàn bộ các Pod ứng dụng hiện tại của mình để chúng nhận diện và tự áp dụng MTU mới (`1350`) từ CNI bridge.

### 🔍 Sự cố 2: Lỗi Kernel thiếu driver/module `vxlan` phục vụ Overlay
* **Triệu chứng**: Khi cài đặt Flannel xong, các node không bao giờ chuyển sang trạng thái `Ready`. Xem log của Pod `kube-flannel` báo lỗi:
  ```
  Error introducing route: vxlan: module not found
  ```
  Hoặc:
  ```
  Failed to create flannel.1 interface: link type vxlan not supported
  ```
* **Nguyên nhân**: Hệ điều hành cài trên Node sử dụng một phiên bản Linux Kernel tối giản (chẳng hạn như Alpine Linux, hoặc các bản kernel tùy biến chuyên biệt cho bảo mật) đã bị lược bỏ driver `vxlan.ko` nằm trong nhân Linux. Do đó, hệ thống không thể khởi tạo interface ảo loại `vxlan`.
* **Cách khắc phục**:
  1. SSH vào Node bị lỗi, kiểm tra xem module `vxlan` đã được nạp hay chưa:
     ```bash
     lsmod | grep vxlan
     ```
  2. Nếu chưa có, hãy thử nạp thủ công bằng lệnh:
     ```bash
     sudo modprobe vxlan
     ```
     Nếu hệ thống báo lỗi không tìm thấy module, bạn cần cài đặt thêm package chứa các driver mạng rộng của kernel:
     - Trên **Ubuntu/Debian**:
       ```bash
       sudo apt-get update && sudo apt-get install -y linux-modules-extra-$(uname -r)
       sudo modprobe vxlan
       ```
  3. Đảm bảo module tự động nạp khi khởi động lại VM:
     ```bash
     echo "vxlan" | sudo tee -a /etc/modules
     ```

---

## ✅ Tổng kết

Bài lab chứng minh bằng thực nghiệm:
1. **VXLAN = UDP tunnel**: Outer packet chứa Node IP, inner packet chứa Pod IP — tcpdump thấy cả hai.
2. **50 bytes overhead = thực**: Kernel enforce MTU 1450 để nhường chỗ cho 50 bytes bọc ngoài.
3. **Tối ưu TCP MSS**: Pod tự động đàm phán TCP MSS = 1410 giúp packet đi qua mạng trơn tru không bị phân mảnh.
