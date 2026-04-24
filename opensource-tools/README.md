# 🛠 Opensource Tools - Công cụ Vận hành, Giám sát & Kiểm thử

Chào mừng bạn đến với thư mục **Opensource Tools**! Thư mục này là nơi tổng hợp, giới thiệu và hướng dẫn sử dụng các công cụ mã nguồn mở (Open-source) tinh túy nhất dành cho kỹ sư Hệ thống, Mạng và DevOps.

Thay vì phải tự xây dựng mọi thứ từ con số 0 hoặc mua các giải pháp thương mại đắt đỏ, cộng đồng open-source đã cung cấp cho chúng ta những "vũ khí" cực kỳ sắc bén để giải quyết các bài toán từ triển khai, vận hành, cho đến giám sát và khắc phục sự cố hệ thống.

---

## 📚 1. Các công cụ đã có tài liệu hướng dẫn

Dưới đây là danh sách các công cụ đã được soạn thảo tài liệu chi tiết. Nhấn vào **Thư mục** để xem slide giới thiệu, cấu hình mẫu và kịch bản thực hành của từng công cụ.

| Tên công cụ | Nhóm chức năng | Mô tả ngắn gọn | Thư mục |
| :--- | :--- | :--- | :--- |
| **Multipass** | Vận hành & Tự động hóa | Giải pháp tạo máy ảo (Full-VM) siêu tốc của Canonical trên Windows/macOS/Linux. | [📂 `./multipass`](./multipass) |
| **MTR** | Kiểm thử & Xử lý sự cố | Khám bệnh mạng toàn diện. Sự kết hợp hoàn hảo giữa Ping và Traceroute. | [📂 `./mtr`](./mtr) |

---

## 💡 2. Các công cụ đề xuất (Sẽ cập nhật)

Dưới đây là danh sách các công cụ vô cùng hữu ích trong thực tế, dự kiến sẽ được bổ sung tài liệu hướng dẫn trong thời gian tới. Các công cụ có biểu tượng ⭐️ là những công cụ **trọng điểm** sẽ được sử dụng xuyên suốt trong series **Kubernetes Networking**.

| Tên công cụ | Nhóm chức năng | Mô tả ngắn gọn | Trạng thái |
| :--- | :--- | :--- | :--- |
| ⭐️ **Vagrant** | Vận hành & Tự động hóa | Công cụ tạo môi trường máy ảo linh hoạt, dùng để dựng Lab K8s Node. | *(Đang cập nhật)* |
| ⭐️ **nicolaka/netshoot** | Kiểm thử & Xử lý sự cố | "Dao Thụy Sĩ" Container chứa tcpdump, tshark, iperf để debug mạng Pod. | *(Đang cập nhật)* |
| ⭐️ **Wireshark / tcpdump**| Kiểm thử & Xử lý sự cố | Phân tích mổ xẻ gói tin, bắt lỗi MTU, VXLAN, IPIP trong mạng K8s. | *(Đang cập nhật)* |
| ⭐️ **iPerf3** | Kiểm thử & Xử lý sự cố | Công cụ chuẩn mực để benchmark throughput/độ trễ giữa các CNI. | *(Đang cập nhật)* |
| ⭐️ **Hubble / Inspektor Gadget** | Giám sát & Khả năng quan sát | Khai thác sức mạnh eBPF để theo dõi kernel, bắt gói tin Layer 7. | *(Đang cập nhật)* |
| **Ansible** | Vận hành & Tự động hóa | Quản lý cấu hình (Configuration Management) không cần agent qua SSH. | *(Đang cập nhật)* |
| **Terraform** | Vận hành & Tự động hóa | Infrastructure as Code (IaC) để khởi tạo hạ tầng Cloud/On-premise. | *(Đang cập nhật)* |
| **Prometheus & Grafana** | Giám sát & Khả năng quan sát | Hệ thống thu thập metric (chuỗi thời gian) và trực quan hóa dữ liệu. | *(Đang cập nhật)* |
| **LibreNMS** | Giám sát & Khả năng quan sát | Giám sát mạng truyền thống, hỗ trợ thu thập mạnh mẽ qua giao thức SNMP. | *(Đang cập nhật)* |
| **K6 (Grafana)** | Kiểm thử & Xử lý sự cố | Công cụ Load testing hệ thống Web/API hiện đại bằng Javascript. | *(Đang cập nhật)* |

---

## 📂 Cấu trúc thư mục tương lai

Mỗi công cụ khi được hoàn thiện sẽ có một thư mục con riêng chứa:
- **Bài viết/Slide giới thiệu & Phân tích Use-case:** Tại sao nên dùng công cụ này? Áp dụng thực tế thế nào?
- **Các file cấu hình mẫu:** (Ví dụ: `docker-compose.yml`, `prometheus.yml`, `Vagrantfile` v.v.).
- **Kịch bản Lab thực hành:** Hướng dẫn step-by-step để bạn tự trải nghiệm trực tiếp.

> **💡 Bạn có công cụ nào hay muốn chia sẻ?**
> Hãy thoải mái tạo Pull Request để đóng góp bài viết hướng dẫn về công cụ yêu thích của bạn vào thư mục này nhé!
