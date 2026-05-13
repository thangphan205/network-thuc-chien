# Lab Tập 4: Thuế "ndots:5" và Tối ưu DNS trong K8s

Trong Kubernetes, DNS là xương sống để các Service tìm thấy nhau. Tuy nhiên, đằng sau sự tiện lợi đó là một cơ chế phân giải tên miền khá cồng kềnh tên là **`ndots:5`**. 

Bài Lab này sẽ dùng `tcpdump` để đếm "bằng chứng phạm tội" của `ndots:5`, sau đó hướng dẫn bạn 3 cách để tối ưu hóa hiệu năng DNS cho K8s.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s 3 node đã hoạt động bình thường.
- `pod-a` từ Tập 2 vẫn đang chạy (vì image `netshoot` có cài sẵn `tcpdump` và `nslookup`).
- (Tuỳ chọn) Nếu lỡ xóa `pod-a`, bạn có thể tạo lại bằng lệnh: `kubectl run pod-a --image=nicolaka/netshoot -- sleep infinity`

---

## 🔬 Thí nghiệm 1: Vạch trần "Thuế ndots:5" bằng Tcpdump

Chúng ta sẽ đo số lượng bản tin DNS thừa thãi mà `pod-a` ném ra mạng khi muốn gọi một domain bên ngoài (ví dụ: `google.com` hoặc `httpbin.org`).

1. **Mở Terminal 1** (SSH vào `controlplane`), đóng vai trò làm máy nghe lén `tcpdump`:
   ```bash
   kubectl exec -it pod-a -- tcpdump -i any -n udp port 53
   ```
   *(Lệnh này sẽ treo ở đó và in ra bất kỳ gói tin DNS (UDP port 53) nào ra/vào Pod).*

2. **Mở Terminal 2** (Cũng SSH vào `controlplane`), đóng vai trò làm user gửi request:
   ```bash
   kubectl exec pod-a -- curl -s -o /dev/null https://httpbin.org/ip
   ```

3. **Quay lại Terminal 1**, phân tích log và bấm `Ctrl+C` để dừng tcpdump:
   *Nhận xét:* Để ý kĩ, bạn sẽ thấy cho một lần `curl` duy nhất, hệ thống đã gửi ra tận **4 lượt truy vấn (queries)**!
   - Lượt 1: Hỏi `httpbin.org.default.svc.cluster.local` (Trả về NXDomain - Lỗi)
   - Lượt 2: Hỏi `httpbin.org.svc.cluster.local` (Lỗi)
   - Lượt 3: Hỏi `httpbin.org.cluster.local` (Lỗi)
   - Lượt 4: Hỏi đích danh `httpbin.org.` (Thành công!)

> **Kết luận:** Vì chuỗi `httpbin.org` chỉ có 1 dấu chấm (nhỏ hơn 5 - `ndots:5`), K8s lầm tưởng đây là domain nội bộ viết tắt, nên nó cố gắng nhét thêm đuôi `.svc.cluster.local` vào để hỏi. Đây chính là "thuế" tài nguyên cực kỳ lãng phí khi gọi External API!

---

## 🚀 Thí nghiệm 2: Tối ưu DNS bằng FQDN (Fully Qualified Domain Name)

Cách rẻ nhất và nhanh nhất để "trốn thuế" là tự mình thêm một dấu chấm `.` vào cuối domain để nói với K8s rằng: *"Đây là tên miền tuyệt đối rồi, đừng thêm đuôi nội bộ vào nữa!"*

**Trên Terminal `controlplane`:**

1. Chạy lại `tcpdump` trên **Terminal 1**:
   ```bash
   kubectl exec -it pod-a -- tcpdump -i any -n udp port 53
   ```

2. Sang **Terminal 2**, chạy lệnh `curl` nhưng thêm dấu chấm cuối vào domain (`httpbin.org.`):
   ```bash
   kubectl exec pod-a -- curl -s -o /dev/null https://httpbin.org./ip
   ```

3. **Quay lại Terminal 1** và quan sát:
   *Kết quả:* Chỉ có đúng **1 lượt truy vấn duy nhất** được gửi đi và trả về thành công ngay lập tức! Bạn đã x4 tốc độ phân giải DNS cho app của mình.

---

## 🛡 Thí nghiệm 3: Tối ưu DNS bằng dnsConfig (Giảm ndots)

Nếu không thể bắt Dev sửa lại Source Code (thêm dấu chấm), người quản trị K8s có thể cấu hình thông số `ndots` trực tiếp vào Pod thông qua YAML.

**Trên Terminal `controlplane`:**

1. Tạo một Pod mới (tên `pod-ndots2`) được ép mức `ndots:2`:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: Pod
   metadata:
     name: pod-ndots2
   spec:
     dnsConfig:
       options:
       - name: ndots
         value: "2"       # Đã giảm từ 5 xuống 2!
     containers:
     - name: netshoot
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF
   ```

2. Đợi vài giây rồi kiểm tra ruột của file cấu hình DNS bên trong Pod mới này:
   ```bash
   kubectl exec pod-ndots2 -- cat /etc/resolv.conf
   ```
   *Kết quả:* Dòng cuối cùng của file sẽ hiển thị là `options ndots:2`.

3. Thử nghiệm: Domain `api.github.com` (có 2 dấu chấm). Vì số lượng dấu chấm đã bằng hoặc lớn hơn mức quy định (2), nó sẽ không bị nối đuôi linh tinh nữa mà chọc thẳng ra Internet luôn!

---

## 💡 Khám phá thêm (Tuỳ chọn): NodeLocal DNSCache

Ở môi trường Production (hàng ngàn Pods), CoreDNS thường xuyên bị quá tải vì phải hứng DNS từ toàn cụm. Kiến trúc **NodeLocal DNSCache** ra đời để giải quyết triệt để chuyện này bằng cách chạy 1 DNS Cache siêu nhẹ trên MỖI NODE (địa chỉ IP ảo `169.254.20.10`). 

*Bạn có thể xem cách Deploy công nghệ xịn sò này ở Slide số 11 (Tập 4).*

---

## ✅ Tổng kết

Tóm lại, để ứng dụng chạy mượt mà và không lãng phí CPU cho mạng:
1. Đối với Service nội bộ (ví dụ: gọi sang service DB): Hãy cứ gọi tên ngắn `db`, luật `ndots:5` sẽ phát huy tác dụng giúp tự điền đuôi `db.default.svc...`.
2. Đối với API bên ngoài (Third-party, Internet): Nhớ thêm **dấu chấm ở cuối**, hoặc phải cấu hình giảm `ndots` trên file YAML của Deployment!
