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