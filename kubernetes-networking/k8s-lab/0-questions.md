# Các câu hỏi trong bài

## Tập 1
### Tại sao cni0 chỉ có ở worker node mà không có ở controlplane?

Đây là một câu hỏi quan sát cực kỳ sắc sảo! Sự vắng mặt của cni0 trên Control Plane liên quan trực tiếp đến cơ chế hoạt động lười biếng (lazy creation) của CNI và luật lập lịch (Scheduler) của Kubernetes.

Dưới đây là 3 lý do giải thích tại sao bạn lại thấy hiện tượng này:

1. Kubelet chỉ tạo cni0 khi có Pod cần dùng mạng
Bridge cni0 không được tạo ra ngay lập tức khi bạn cài đặt Flannel. Nó chỉ được CNI plugin tạo ra khi và chỉ khi có ít nhất một Pod (thông thường) được lập lịch (schedule) chạy trên Node đó. Nếu Kubelet trên Node không nhận được lệnh chạy Pod nào cần cấp IP, nó sẽ không gọi CNI, và cni0 sẽ không được sinh ra.

2. Control Plane bị "Cấm" chạy Pod (Taint: NoSchedule)
Theo mặc định, khi bạn cài đặt bằng kubeadm, node Control Plane sẽ bị đánh một cái nhãn xua đuổi (Taint) mang tên node-role.kubernetes.io/control-plane:NoSchedule. Taint này ngăn cản mọi Pod ứng dụng của bạn (như Nginx, web app...) chạy trên Control Plane để bảo lưu tài nguyên cho hệ điều hành và các Core component (như kube-apiserver). Do đó, Control Plane thường không có Pod nào chạy.

3. Sự trùng hợp ngẫu nhiên của CoreDNS
Bạn có thể thắc mắc: "Thế còn CoreDNS (Pod hệ thống) thì sao? Nó cũng cần mạng mà?" Đúng vậy! CoreDNS là một ngoại lệ, nó có cấu hình Toleration cho phép chạy xuyên qua cái Taint cấm kia. Tuy nhiên, nếu ở Bước 1 & Bước 2 bạn đã join các Worker nodes vào cụm xong xuôi rồi mới cài CNI, thì khi CNI cài xong, K8s Scheduler thấy cụm có 3 Nodes (1 controlplane, 2 worker) và nó quyết định quăng 2 cục Pod CoreDNS sang bên worker1 hoặc worker2 để chạy.

👉 Kết luận: Vì CoreDNS bị đẩy sang Worker, và các Pod khác thì bị Taint cấm chạy trên Control Plane, dẫn đến Control Plane của bạn trắng tay, không có bất kỳ một Pod nào cần IP. Kubelet nằm chơi xơi nước, CNI không được gọi, và kết quả là cni0 không hề tồn tại trên Control Plane!

Cách kiểm chứng: Nếu bạn xóa cái Taint cấm chạy trên Control Plane đi: kubectl taint nodes controlplane node-role.kubernetes.io/control-plane:NoSchedule- Rồi tạo một Pod Nginx. Ngay khi Pod đó rơi vào Control Plane, bùm! Bridge cni0 sẽ lập tức xuất hiện.

(Card flannel.1 thì ngược lại, nó là thành phần cốt lõi của Overlay Network nên DaemonSet của Flannel sẽ luôn khởi tạo nó ngay từ đầu trên mọi Node để sẵn sàng làm VTEP).

## Tập 2
### Tại sao trong Pod chỉ có 1 interface eth0 mà lại tạo các route /16, sao không cho chạy qua default route?

Về mặt kết quả cuối cùng, nếu xóa dòng `10.244.0.0/16 via 10.244.1.1` đi thì gói tin gửi sang Pod khác (ví dụ `10.244.2.5`) vẫn sẽ rơi vào `default route` và đi ra đúng cái cổng `10.244.1.1` (bridge `cni0` của Node). 

Tuy nhiên, CNI (Flannel/Calico) cần thêm một route explicit `/16` **ngay bên trong bảng định tuyến của Pod** để giải quyết 3 bài toán sau:

1. Nguyên tắc "Specific Route" (Chống đè Default Route)
Nếu bạn chạy một Pod chứa ứng dụng OpenVPN (hoặc một proxy/VPN client). Ứng dụng này khi khởi động lên bên trong Pod sẽ cố tình sửa đổi `default route` (đẩy `0.0.0.0/0` qua card mạng ảo `tun0` của nó thay vì `eth0`). 
- Nếu không có dòng `/16`: Toàn bộ traffic nói chuyện với các Pod khác trong cụm K8s cũng sẽ bị chui xuống hầm VPN và đứt kết nối hoàn toàn.
- Nhờ CNI đã "cắm cọc" sẵn dòng `/16`: Theo luật Longest Prefix Match, route `/16` cụ thể hơn route `default` (`0.0.0.0/0`). Nên cho dù `default route` có bị app bẻ đi đâu, traffic nội bộ K8s vẫn luôn đi qua `eth0`. Cái route `/16` này đóng vai trò như một mỏ neo (anchor) bảo vệ traffic K8s.

2. Tối ưu kích thước gói tin (MTU) ngay từ bên trong Pod
Khi ứng dụng của bạn tạo ra một gói dữ liệu lớn, TCP Stack của Linux bên trong Pod sẽ nhìn vào bảng định tuyến để biết nên cắt nhỏ gói tin ra kích thước bao nhiêu (fragment).
Traffic đi Internet (North-South) và traffic đi nội bộ (East-West qua Flannel VXLAN) có MTU khác nhau. Nếu dùng chung `default route`, TCP Stack sẽ cắt gói tin theo MTU 1500. Khi gói tin này ra đến Node, Node bọc thêm 50 byte VXLAN Header thành 1550 byte 👉 Vượt ngưỡng cho phép, gói tin bị rớt hoặc phân mảnh gây giảm hiệu năng.
Việc tách riêng route `/16` cho phép CNI ép thông số `mtu 1450` riêng cho dải IP cụm ngay từ trong Pod, giúp TCP Stack tự cắt nhỏ gói tin chuẩn xác.

3. Chuẩn bị cho Pod có nhiều Card mạng (Multus CNI)
Trong thực tế (như các công ty viễn thông), một Pod có thể được cắm thêm `net1`, `net2`... (ví dụ kết nối mạng SR-IOV tốc độ cao). 
Khi Pod có 3 card mạng, ai sẽ là người nói cho Pod biết "Nếu gọi Pod khác thì đi đường nào? Ra Internet thì đi đường nào?". Chính cái route `/16 dev eth0` này là biển chỉ đường cứng để đảm bảo traffic nội bộ K8s luôn đi đúng card `eth0` chứ không lạc sang card khác!

## Tập 6
### Tại sao trong Sự cố 2, khi xóa file cấu hình CNI `10-flannel.conflist` làm Node chuyển sang NotReady, nhưng các Pod đang chạy vẫn có thể ping thông suốt chéo Node?

Đây là một câu hỏi quan sát cực kỳ xuất sắc! Hiện tượng này phản ánh chính xác sự phân tách độc lập (decoupling) giữa **Control Plane (Tầng điều khiển)** và **Data Plane (Tầng truyền tải dữ liệu)** trong Kubernetes:

1. **Tầng Control Plane (Kubelet và file cấu hình CNI)**:
   - File cấu hình `/etc/cni/net.d/10-flannel.conflist` là "cầu nối" để Kubelet tương tác với CNI plugin khi có sự kiện thay đổi Pod (Tạo mới hoặc Xóa bỏ). Kubelet cũng quét thư mục này định kỳ để kiểm tra xem hệ thống mạng của Node có sẵn sàng hay không.
   - Khi file này bị xóa, tiến trình Kubelet kiểm tra sức khỏe mạng thất bại $\rightarrow$ lập tức báo cáo trạng thái `NetworkReady=false` về API Server $\rightarrow$ Node bị đánh dấu **`NotReady`** nhằm ngăn không cho Scheduler lập lịch cho Pod mới chui vào Node bị lỗi cấu hình mạng.

2. **Tầng Data Plane (Linux Kernel Space)**:
   - Các Pod đang chạy (như `pod-a`) **đã được thiết lập mạng xong xuôi từ trước đó**.
   - Interface ảo `eth0` trong Pod, cặp dây mạng ảo **veth pair** nối ra Host, bridge `cni0`, và card ảo `flannel.1` (VTEP) cùng các bảng tra cứu tĩnh (**Route, ARP, FDB**) đã được Linux Kernel ghi nhớ trực tiếp vào bộ nhớ RAM của hệ điều hành.
   - Khi `pod-b` gửi gói tin ping sang `pod-a`, gói tin đi qua card mạng vật lý `eth0` của Node, được nhân Linux giải mã VXLAN trên card ảo `flannel.1`, định tuyến qua bridge `cni0` và chui vào Pod hoàn toàn ở **tầng Kernel Space**.

👉 **Kết luận:** Toàn bộ quá trình truyền dữ liệu (Data Plane) được thực thi trực tiếp bởi Linux Kernel, hoàn toàn không đi qua Kubelet hay tiến trình User Space nào, và cũng không cần đọc file `/etc/cni/net.d/10-flannel.conflist` nữa. Nhờ vậy, mạng lưới Pod đã chạy vẫn thông suốt kể cả khi cấu hình CNI của Node bị hỏng!

### Tại sao khi Node bị NotReady (do thiếu file cấu hình CNI), các Pod bị xóa sẽ bị kẹt ở trạng thái `Terminating`, nhưng ngay sau khi ta khôi phục lại file cấu hình CNI, Pod đó lại lập tức biến mất sạch sẽ?

Đây là một câu hỏi thực chiến cực kỳ sâu sắc, tiếp tục chứng minh vai trò không thể thiếu của CNI trong **vòng đời dọn dẹp tài nguyên (Teardown lifecycle)** của Kubernetes:

1. **Tại sao Pod bị kẹt ở trạng thái `Terminating`?**
   - Khi bạn chạy lệnh xóa Pod (`kubectl delete pod`), Kubelet trên Node nhận được chỉ thị. Để xóa Pod một cách sạch sẽ và an toàn, Kubelet bắt buộc phải **giải phóng toàn bộ tài nguyên mạng của Pod đó trước**.
   - Hành động giải phóng này bao gồm: thu hồi địa chỉ IP đã cấp phát (xóa file IPAM lease), nhổ cặp veth pair ra khỏi bridge `cni0` và xóa namespace mạng.
   - Để thực hiện các công việc này, Kubelet **phải đọc file cấu hình CNI `/etc/cni/net.d/10-flannel.conflist`** để biết cách gọi CNI plugin thực thi lệnh dọn dẹp (`DEL` command).
   - Vì file này đã bị di chuyển hoặc xóa đi, Kubelet bị "mù" cấu hình và báo lỗi, không thể dọn dẹp mạng cho Pod. Do đó, Kubelet từ chối kết thúc tiến trình xóa container và không báo cáo hoàn tất về API Server. Pod bị kẹt cứng ở trạng thái `Terminating` trên API Server.

2. **Tại sao Pod tự động biến mất khi file CNI được khôi phục?**
   - Kubernetes hoạt động theo mô hình **Reconciliation Loop (vòng lặp đồng bộ)** liên tục. Kubelet liên tục cố gắng đưa trạng thái thực tế của Node về đúng trạng thái mong muốn (mong muốn là Pod phải được xóa sạch).
   - Ngay sau khi bạn di chuyển file `10-flannel.conflist` quay trở lại thư mục `/etc/cni/net.d/`, Kubelet lập tức phát hiện cấu hình CNI đã khả dụng.
   - Ở vòng lặp tiếp theo, Kubelet gọi thành công CNI CNI plugin để thực thi dọn dẹp card mạng, xóa sạch container và báo cáo thành công về API Server.
   - Pod lập tức biến mất hoàn toàn khỏi danh sách của bạn chỉ sau vài giây mà không cần bất kỳ lệnh can thiệp thủ công nào!