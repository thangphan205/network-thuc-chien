# Lab Tập 4: Vấn đề "ndots:5" và Tối ưu DNS trong K8s

Trong Kubernetes, DNS là xương sống để các Service tìm thấy nhau. Tuy nhiên, đằng sau sự tiện lợi đó là một cơ chế phân giải tên miền khá cồng kềnh tên là **`ndots:5`**. 

Bài Lab này sẽ dùng `tcpdump` để đếm "bằng chứng phạm tội" của `ndots:5`, sau đó hướng dẫn bạn 3 cách để tối ưu hóa hiệu năng DNS cho K8s.

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s 3 node đã hoạt động bình thường.
- `pod-a` từ Tập 2 vẫn đang chạy (vì image `netshoot` có cài sẵn `tcpdump` và `nslookup`).
- (Tuỳ chọn) Nếu lỡ xóa `pod-a`, bạn có thể tạo lại bằng lệnh: `kubectl run pod-a --image=nicolaka/netshoot -- sleep infinity`

---

## 🔬 Thí nghiệm 1: Vạch trần "Vấn đề ndots:5" bằng Tcpdump

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

> **Kết luận:** Vì chuỗi `httpbin.org` chỉ có 1 dấu chấm (nhỏ hơn 5 - `ndots:5`), K8s lầm tưởng đây là domain nội bộ viết tắt, nên nó cố gắng nhét thêm đuôi `.svc.cluster.local` vào để hỏi. Đây chính là lãng phí tài nguyên cực kỳ tốn kém khi gọi External API!

---

## 🚀 Thí nghiệm 2: Tối ưu DNS bằng FQDN (Fully Qualified Domain Name)

Cách rẻ nhất và nhanh nhất để tối ưu DNS là tự mình thêm một dấu chấm `.` vào cuối domain để nói với K8s rằng: *"Đây là tên miền tuyệt đối rồi, đừng thêm đuôi nội bộ vào nữa!"*

**Trên Terminal `controlplane`:**

1. Chạy lại `tcpdump` trên **Terminal 1**:
   ```bash
   kubectl exec -it pod-a -- tcpdump -i any -n udp port 53
   ```

2. Sang **Terminal 2**, chạy lệnh `curl` nhưng thêm dấu chấm cuối vào domain (`httpbin.org.`). Chúng ta dùng giao thức `http` thay vì `https` để tránh lỗi đối khớp chứng chỉ SSL/TLS (vốn chỉ cấp cho `httpbin.org` chứ không phải `httpbin.org.`):
   ```bash
   kubectl exec pod-a -- curl -s -o /dev/null http://httpbin.org./ip
   ```

3. **Quay lại Terminal 1** và quan sát:
   *Kết quả:* Chỉ có đúng **1 lượt truy vấn duy nhất** được gửi đi và trả về thành công ngay lập tức! Bạn đã giảm từ 4 queries xuống còn 1 — tiết kiệm 75% số DNS round-trip tới CoreDNS!

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

3. Chạy lại `tcpdump` trên **Terminal 1** để xác nhận:
   ```bash
   kubectl exec -it pod-ndots2 -- tcpdump -i any -n udp port 53
   ```

4. Sang **Terminal 2**, gọi `api.github.com` (2 dấu chấm — bằng mức `ndots:2`):
   ```bash
   kubectl exec pod-ndots2 -- curl -s -o /dev/null http://api.github.com
   ```

5. Quay lại **Terminal 1** quan sát: chỉ có **1 query duy nhất** đến `api.github.com.` — không có query nối đuôi `svc.cluster.local` nào cả!

6. Dọn dẹp:
   ```bash
   kubectl delete pod pod-ndots2
   ```

---

## 🔍 Thí nghiệm 4: Headless Service — DNS phân giải thẳng đến Pod IP

Không phải Service nào cũng cần VIP (ClusterIP). **Headless Service** (`clusterIP: None`) bỏ qua kube-proxy hoàn toàn — CoreDNS trả về trực tiếp IP của các Pod đứng sau.

**Trên Terminal `controlplane`:**

1. Tạo Headless Service trỏ vào nginx deployment (vẫn đang chạy từ Tập 3, nếu không thì tạo lại):
   ```bash
   kubectl create deployment nginx --image=nginx --replicas=2 2>/dev/null || true
   kubectl expose deployment nginx --port=80 --cluster-ip=None --name=nginx-headless
   ```

2. Kiểm tra Service: `CLUSTER-IP` sẽ là `None`:
   ```bash
   kubectl get svc nginx-headless
   # NAME             TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
   # nginx-headless   ClusterIP   None         <none>        80/TCP    5s
   ```

3. Resolve tên miền của Headless Service từ `pod-a`:
   ```bash
   kubectl exec pod-a -- nslookup nginx-headless
   ```
   *Kết quả:* Thay vì trả về 1 ClusterIP duy nhất như Service thường, `nslookup` trả về **nhiều địa chỉ IP** — mỗi IP là IP thật của 1 Pod nginx!

4. So sánh với ClusterIP Service thông thường (nếu còn `nginx` Service từ Tập 3):
   ```bash
   kubectl exec pod-a -- nslookup nginx
   # → Trả về 1 IP duy nhất (ClusterIP của kube-proxy)
   kubectl exec pod-a -- nslookup nginx-headless
   # → Trả về N IPs (IP thật của từng Pod)
   ```

> **Ứng dụng thực tế:** StatefulSet dùng Headless Service để client kết nối thẳng đến Pod cụ thể (ví dụ: `pod-0.nginx-headless`). Kafka, Cassandra, etcd đều dùng cơ chế này.
>
> **Lưu ý:** Lab này dùng Deployment cho đơn giản, nhưng trong thực tế Headless Service phát huy sức mạnh nhất với **StatefulSet** — vì StatefulSet đặt tên Pod cố định (`pod-0`, `pod-1`...), cho phép client kết nối trực tiếp đến từng replica qua DNS `pod-0.nginx-headless.default.svc.cluster.local`. Deployment có Pod name ngẫu nhiên nên không dùng được tính năng này.

5. Dọn dẹp:
   ```bash
   kubectl delete svc nginx-headless
   kubectl delete deployment nginx
   ```

---

## 💡 Khám phá thêm (Tuỳ chọn): NodeLocal DNSCache

Ở môi trường Production (hàng ngàn Pods), CoreDNS thường xuyên bị quá tải vì phải hứng DNS từ toàn cụm. Kiến trúc **NodeLocal DNSCache** ra đời để giải quyết triệt để chuyện này bằng cách chạy 1 DNS Cache siêu nhẹ trên MỖI NODE (địa chỉ IP ảo `169.254.20.10`). 

*Bạn có thể tìm hiểu thêm tại [tài liệu chính thức của Kubernetes về NodeLocal DNSCache](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/).*

---

## ✅ Tổng kết

Tóm lại, để ứng dụng chạy mượt mà và không lãng phí CPU cho mạng:
1. Đối với Service nội bộ (ví dụ: gọi sang service DB): Hãy cứ gọi tên ngắn `db`, luật `ndots:5` sẽ phát huy tác dụng giúp tự điền đuôi `db.default.svc...`.
2. Đối với API bên ngoài (Third-party, Internet): Nhớ thêm **dấu chấm ở cuối**, hoặc phải cấu hình giảm `ndots` trên file YAML của Deployment!
