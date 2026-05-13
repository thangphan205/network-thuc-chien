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