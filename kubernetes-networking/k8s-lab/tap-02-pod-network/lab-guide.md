# Lab Tập 2: Pod Network, Pause Container & veth pair

Bài lab này sẽ giúp bạn bóc tách kiến trúc mạng bên trong một Pod, chứng minh vai trò của `pause container` và cách sợi cáp ảo `veth pair` nối Pod ra ngoài thế giới (thông qua `cni0`).

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s 3 node đã cài đặt CNI Flannel và đang ở trạng thái `Ready` (kết quả từ Tập 01).

---

## 🚀 Thực nghiệm 1: Khởi tạo Pods để quan sát
Chúng ta sẽ tạo 2 Pods sử dụng image `nicolaka/netshoot` (một image chứa đầy đủ đồ chơi debug mạng) và cố tình gán chúng lên 2 worker khác nhau.

1. SSH vào `controlplane`:
   ```bash
   multipass shell controlplane
   ```

2. Tạo `pod-a` trên `worker1` và `pod-b` trên `worker2`:
   ```bash
   kubectl run pod-a --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker1"}}' -- sleep infinity
   kubectl run pod-b --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"worker2"}}' -- sleep infinity
   ```

3. Chờ Pod chạy và kiểm tra IP của chúng:
   ```bash
   kubectl wait --for=condition=Ready pod/pod-a pod/pod-b --timeout=60s
   kubectl get pods -o wide
   ```
   *Ghi chú lại IP của `pod-a` (ví dụ: 10.244.1.5) để dùng cho các bước sau.* Thoát khỏi `controlplane`.

---

## 🔬 Thực nghiệm 2: Khám phá "thế giới ngầm" bằng nsenter
Chúng ta sẽ lẻn vào network namespace của `pod-a` từ bên ngoài Node mà không cần dùng lệnh `kubectl exec` hay chui vào shell của container.

1. SSH vào `worker1` (nơi đang chạy `pod-a`):
   ```bash
   multipass shell worker1
   ```

2. Tìm `pause container` của `pod-a` và lấy PID của nó:
   ```bash
   # Lấy Pod Sandbox ID (chính là pause container)
   PAUSE_ID=$(sudo crictl pods --name pod-a -q)
   
   # Lấy PID thực sự của tiến trình trên hệ điều hành bằng cách parse JSON
   PAUSE_PID=$(sudo crictl inspectp $PAUSE_ID | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['pid'])")
   echo "Pause PID: $PAUSE_PID"
   ```

3. Dùng công cụ `nsenter` để chạy lệnh `ip addr` bên trong Network Namespace của Pod:
   ```bash
   sudo nsenter -t $PAUSE_PID -n ip addr
   sudo nsenter -t $PAUSE_PID -n ip route
   ```
   *Nhận xét:* Bạn sẽ thấy chính xác địa chỉ IP của `pod-a`. Điều này chứng tỏ Network Namespace thực sự thuộc về `pause container`.

4. Quan sát kỹ output của `ip route`. Ngoài `default` route và route `/24` local, bạn sẽ thấy thêm một dòng:
   ```
   10.244.0.0/16 via 10.244.1.1 dev eth0
   ```
   **Câu hỏi suy nghĩ:** Tại sao CNI cài thêm route `/16` này trong khi có vẻ như `default route` đã đủ? Ghi lại suy nghĩ của bạn rồi đọc phần giải thích ở `questions.md`.

---

## 🔗 Thực nghiệm 3: Dây cáp ảo (veth pair) và Bridge

Vẫn ở trên `worker1`, chúng ta đi tìm đầu còn lại của sợi cáp nối từ Pod ra ngoài host.

1. Liệt kê các card mạng loại `veth` trên Node:
   ```bash
   ip link show type veth
   ```
   *Bạn sẽ thấy một card mạng có tên bắt đầu bằng `veth` (VD: `veth3a1b2c...`). Chú ý chỉ số `@if...` của nó, đây chính là đầu nối ra ngoài host của card mạng `eth0` bên trong Pod.*

2. Kiểm tra xem sợi `veth` này được cắm vào đâu:
   ```bash
   ip link show master cni0
   ```
   *Nhận xét:* Bạn sẽ thấy sợi `veth` kia đang được gắn (master) vào switch ảo `cni0`.

3. Ping trực tiếp vào IP của `pod-a` từ Node (chứng minh Nguyên tắc 2: Node-to-Pod không NAT):
   ```bash
   ping -c 3 <IP_CỦA_POD_A>
   ```
   *Kết quả:* Ping thành công ngay lập tức! Thoát khỏi `worker1`.

---

## 💥 Thực nghiệm 4: Sức mạnh của Pause Container (Anchor)

Điều gì xảy ra nếu ứng dụng của bạn (App container) bị crash? Liệu IP của Pod có bị mất đi và cấp lại không? Hãy cùng giả lập tình huống này.

1. Đứng tại **`controlplane`**, kiểm tra IP và số lần Restart hiện tại của Pod:
   ```bash
   kubectl get pod pod-a -o wide
   ```
   *Bạn hãy ghi nhớ lại cột IP và cột RESTARTS (lúc này đang là 0).*

2. Trước khi kill, mở một terminal theo dõi realtime:
   ```bash
   # Terminal 1 - controlplane
   kubectl get pod pod-a -w
   ```

3. Trên terminal thứ 2, SSH vào `worker1` và kill app container qua container runtime:
   ```bash
   # Terminal 2 - worker1
   APP_ID=$(sudo crictl ps --name pod-a -q)
   sudo crictl stop $APP_ID
   ```
   > **Tại sao dùng `crictl stop` thay vì `kubectl exec -- kill -9 1`?**
   > `kubectl exec` JOIN vào PID namespace của container. Linux kernel **silently drop SIGKILL** gửi tới PID 1 từ bên trong cùng PID namespace — đây là cơ chế bảo vệ để namespace không tự phá hủy chính nó. Chỉ process từ parent namespace bên ngoài (như `crictl stop` gọi containerd API từ root namespace) mới thực sự kill được PID 1 của container.

4. Quan sát Terminal 1 — bạn sẽ thấy:
   ```
   pod-a   1/1   Running   0   ...   10.244.1.X
   pod-a   0/1   Error     0   ...   10.244.1.X   ← container chết
   pod-a   1/1   Running   1   ...   10.244.1.X   ← restart, IP GIỮ NGUYÊN!
   ```
   Cột `RESTARTS` tăng lên 1, nhưng `IP` **KHÔNG HỀ BỊ ĐỔI**. Pause container đã giữ "mỏ neo" mạng trong suốt quá trình restart!

---

## ✅ Tổng kết
Qua bài lab này, bạn đã tự tay khám phá:
1. `pause container` chính là "kẻ canh giữ" Network Namespace cho toàn bộ Pod.
2. Công cụ `nsenter` rất mạnh mẽ để debug mạng K8s từ mức OS.
3. Cơ chế `veth pair` cắm trực tiếp Pod vào bridge `cni0`.
4. CNI cài route `/16` trong Pod như một "anchor" bảo vệ traffic K8s.

---

## 🤔 Câu hỏi thảo luận
Đọc phần **Tập 2** trong file `../0-questions.md` để đọc giải thích đầy đủ cho câu hỏi: *Tại sao trong Pod chỉ có 1 interface eth0 mà lại tạo các route /16?*

