# 🎙️ Kịch bản Thuyết trình & Speaker Notes — Tập 10
> **Đề tài:** Giải phẫu kiến trúc Calico — Felix, BIRD, Typha
> **Dành cho:** Người thuyết trình / Giảng viên quay video thực hành.
> **Kênh:** Network Thực Chiến (youtube.com/@NetworkThucChien)

---

# 📺 PHẦN I: KỊCH BẢN LỜI DẪN DẪN VÀO BÀI HỌC (INTRO & SLIDES)

## 🎬 1. Lời mở đầu & Trêu mắt (Hook & Intro)
*(Thời gian: 0:00 - 1:30)*

> **[Lời nói của người dẫn]:**
> *"Chào mừng các bạn đã quay trở lại với **Network Thực Chiến**!
>
> Ở Tập 9, chúng ta đã cùng nhau làm một việc rất tuyệt vời: Khởi tạo một cụm Kubernetes sạch và cài đặt **Calico CNI** qua Tigera Operator. Chúng ta cũng đã chứng minh được sức mạnh của Calico khi áp dụng chính sách `Default Deny` - ngay lập tức khóa chặt đường đi của hacker, bảo vệ an toàn cho Pod Database của hệ thống. Một việc mà ở các tập trước, Flannel hoàn toàn bất lực.
>
> Nhưng... đã bao giờ các bạn tự hỏi: **Đằng sau bức màn bảo mật đó, Calico đã hoạt động như thế nào chưa?** 
>
> Khi bạn gõ lệnh `kubectl apply -f networkpolicy.yaml`, làm thế nào mà một tệp cấu hình dạng text lại biến thành các bức tường lửa thép chặn đứng gói tin ngay tại Kernel của từng Node trong chưa đầy 100 mili-giây? Những cái tên nghe rất lạ tai như **Felix**, **BIRD**, hay **Typha** là ai, và họ đóng vai trò gì trong bộ máy vận hành khổng lồ này?
>
> Trong Tập 10 ngày hôm nay, chúng ta sẽ không chỉ nói về lý thuyết. Chúng ta sẽ cùng nhau **giải phẫu toàn bộ kiến trúc của Calico**, chui sâu vào Kernel của Linux để 'soi' chi tiết từng chain `cali-*` trong iptables, đồng thời cấu hình công cụ debug huyền thoại `calicoctl` trực tiếp trên hệ thống máy ảo Multipass.
>
> Nếu các bạn đã sẵn sàng làm chủ hạ tầng mạng K8s, chúng ta cùng bắt đầu ngay thôi!"*

---

## 🏗️ 2. Nội dung chính — Ba chàng lính ngự lâm của Calico
*(Thời gian: 1:30 - 4:30)*

> **[Lời nói của người dẫn]:**
> *"Để vận hành một mạng lưới bảo mật và hiệu năng cao, Calico dựa vào ba thành phần cốt lõi chạy trên mỗi Node. Hãy tưởng tượng họ giống như ba chàng lính ngự lâm phối hợp nhịp nhàng với nhau:
>
> *   **Chàng lính thứ nhất — Felix (Người thực thi âm thầm):**
>     Felix chạy dưới dạng một DaemonSet trên từng Node. Đây chính là 'trái tim' của hệ thống an ninh. Felix liên tục lắng nghe (watch) các sự kiện từ Kubernetes API. Ngay khi bạn apply một NetworkPolicy mới, Felix sẽ tính toán và trực tiếp dịch chính sách đó thành các luật chặn lọc gói tin (`iptables` hoặc `eBPF`) ngay tại Kernel của Node đó. Toàn bộ quá trình này diễn ra cực kỳ nhanh - dưới **100 mili-giây**, không cần restart Pod, không cần reboot Node.
>     
> *   **Chàng lính thứ hai — BIRD (Nhà ngoại giao định tuyến):**
>     BIRD là một BGP Daemon chạy song song với Felix. Nhiệm vụ của BIRD là 'giao tiếp' và 'buôn chuyện' với BIRD của các Node khác. Nó sẽ quảng bá: *'Này các bạn, Pod Subnet của tôi là `10.244.1.0/24`, ai muốn gửi gói tin đến đây thì cứ chuyển qua IP vật lý của tôi nhé!'*. Nhờ BIRD chạy giao thức BGP, các Node tự học tuyến đường của nhau và chuyển tiếp gói tin trực tiếp ở tầng L3 mà không cần bọc thêm bất kỳ lớp hầm (Encapsulation) nào như VXLAN, giúp tối ưu hóa băng thông tối đa.
>
> *   **Chàng lính thứ ba — Typha (Người gác cổng API):**
>     Khi cụm của bạn nhỏ (dưới 3 nodes), Felix có thể nói chuyện thẳng với API Server. Nhưng hãy tưởng tượng cụm phình to lên 500 hay 1000 nodes, 1000 ông Felix đồng loạt kết nối và spam truy vấn thì API Server sẽ sập ngay lập tức. **Typha** sinh ra để làm lớp đệm (Cache Proxy). Mọi Felix sẽ kết nối qua Typha, Typha nhận cấu hình một lần từ API Server rồi phân phối (fan-out) xuống cho toàn bộ các Felix bên dưới. Cực kỳ thông minh và scale vô hạn!"*

---

## 📊 3. Thuyết minh Sơ đồ luồng (Sequence Diagram Walkthrough)
*(Thời gian: 4:30 - 6:00)*

> **[Lời nói của người dẫn]:**
> *(Người thuyết trình trỏ vào sơ đồ Mermaid với hai vùng khối màu xanh dương và xanh lá)*
>
> *"Hãy nhìn vào sơ đồ luồng đồng bộ này, các bạn sẽ thấy kiến trúc Calico hoạt động đẹp mắt như thế nào thông qua hai khối luồng độc lập:
>
> *   **Khối màu Xanh Dương ở phía trên chính là Luồng 1 — Đồng bộ Network Policy:** 
>     Khi Quản trị viên apply một chính sách mới qua `kubectl`, sự kiện thay đổi được truyền tới API Server. **Typha** đón lấy sự kiện này, cache lại và đẩy đồng loạt (Fan-out) xuống cho **Felix** trên tất cả các Node. Felix ngay lập tức tính toán và nạp thẳng các luật `cali-*` vào **Linux Kernel** trong nháy mắt.
>     
> *   **Khối màu Xanh Lá ở phía dưới chính là Luồng 2 — Định tuyến BGP:**
>     Khi một Pod local được gán IP, **BIRD** lập tức đọc thông tin IP từ Kernel, sau đó quảng bá dải Pod Subnet này sang các Node khác (Peers) qua cổng BGP 179. BIRD ở các node nhận tin sẽ tự động ghi tuyến đường (Route) chéo node vào Routing Table của mình. 
>     
> Hai bánh răng bảo mật và định tuyến này quay liên tục, tạo nên một hệ thống mạng K8s siêu tốc và cực kỳ an toàn."*

---

## 💻 4. Dẫn nhập thực hành (Transition to Lab)
*(Thời gian: 6:00 - 6:30)*

> **[Lời nói của người dẫn]:**
> *"Lý thuyết như vậy là đã quá rõ ràng rồi! Bây giờ, hãy mở Terminal lên. 
>
> Chúng ta sẽ cùng nhau thực hiện 4 thí nghiệm thực chiến cực kỳ thú vị ngay sau đây:
> 1.  **Xem log của Felix trong thời gian thực** để tự mắt kiểm chứng tốc độ xử lý tính bằng mili-giây.
> 2.  **Liệt kê và giải phẫu các chain `cali-*`** trong iptables để hiểu cách gói tin bị ACCEPT hay DROP.
> 3.  **Cài đặt và sử dụng `calicoctl`** phiên bản mới nhất `v3.32.0` để tương tác trực tiếp với các tài nguyên của Calico.
> 4.  **Kiểm tra hoạt động của Typha** và đếm số lượng kết nối đang chạy.
>
> Các lệnh thực hành chi tiết đã được tôi chuẩn bị đầy đủ trong tệp `lab-guide.md` đi kèm bài học.
>
> Chúng ta cùng SSH vào máy ảo `controlplane` và bắt đầu thôi!"*

---

# 🔬 PHẦN II: HƯỚNG DẪN SPEAKER NOTES TRONG QUÁ TRÌNH LÀM LAB

## 🔬 Thí nghiệm 1: Xem Felix log real-time

### 🖥️ Hành động trên màn hình:
*   Mở hai cửa sổ Terminal xếp cạnh nhau (Side-by-side).
*   Cửa sổ trái: Đăng nhập vào `controlplane`, lấy tên Pod `calico-node` trên `worker1` và chạy lệnh xem logs.
*   Cửa sổ phải: Chuẩn bị lệnh tạo `NetworkPolicy` để sẵn sàng chạy.

### 🗣️ Lời nói của người dẫn (Speaker Script):
> *"Bây giờ, chúng ta sẽ bắt đầu với Thí nghiệm 1. Tôi muốn chứng minh cho các bạn thấy tốc độ phản ứng cực kỳ nhanh của Felix - bộ não chính sách mạng của Calico. Nó hoạt động theo cơ chế hướng sự kiện (Event-driven) chứ không hề thăm dò định kỳ (polling) nên độ trễ gần như bằng không.
>
> (Thao tác gõ lệnh lấy Pod)
> Đầu tiên ở Terminal bên trái, tôi sẽ lấy tên của Pod `calico-node` đang chạy trên `worker1` và chạy lệnh `kubectl logs` để theo dõi nhật ký hoạt động của Felix.
>
> (Chạy lệnh logs)
> Các bạn thấy đấy, logs của Felix đang hiển thị ở đây. Tôi sẽ lọc theo các từ khóa `policy`, `endpoint` và `felix` để chúng ta dễ quan sát.
>
> (Chuyển sang Terminal bên phải)
> Bây giờ, ở cửa sổ bên phải, tôi sẽ áp dụng một chính sách bảo mật mạng cực kỳ đơn giản: `test-policy`. Chính sách này yêu cầu: chỉ cho phép Pod `backend` kết nối vào Pod `frontend`.
>
> (Nhấn Enter để apply)
> Hãy chú ý kỹ vào Terminal bên trái khi tôi nhấn Enter!... Ba, hai, một, chạy!...
>
> (Chỉ tay vào dòng log mới xuất hiện)
> Các bạn nhìn xem! Gần như ngay lập tức, Felix log báo nhận được sự kiện: `policy update: processing 1 policy update(s)`. Và chỉ sau vài mili-giây, nó ghi: `Finished applying policy update in ... ms`.
>
> Không hề có độ trễ, không cần phải khởi động lại bất kỳ dịch vụ hay container nào! Felix đã lắng nghe sự thay đổi của K8s API và biên dịch chính sách này thẳng xuống nhân Kernel của Node thành công. Đây là tốc độ phản ứng ở cấp độ Mili-giây trong thực tế!"*

---

## 🔬 Thí nghiệm 2: Xem iptables chains Felix tạo

### 🖥️ Hành động trên màn hình:
*   Đăng nhập vào `worker1` bằng lệnh `multipass shell worker1`.
*   Chạy lệnh liệt kê iptables chứa từ khóa `cali`.
*   Chạy lệnh xem chi tiết các rule trong chain `cali-FORWARD` và `cali-tw-*`.

### 🗣️ Lời nói của người dẫn (Speaker Script):
> *"Sau khi thấy Felix báo đã đồng bộ xong, câu hỏi tiếp theo là: 'Nó đã ghi vào đâu trong Linux?'
> Để trả lời, tôi sẽ SSH trực tiếp vào `worker1` và dùng quyền root để truy vấn hệ thống lọc gói tin `iptables` của hệ điều hành.
>
> (Chạy lệnh grep "^Chain cali")
> Wow, các bạn nhìn xem! Rất nhiều các Chain mới được bắt đầu bằng tiền tố `cali-` đã được Felix sinh ra tự động. Chúng ta có thể thấy:
> * `cali-FORWARD`: Đây là cửa ngõ chính để điều hướng các gói tin đi qua Node.
> * `cali-from-wl-dispatch` và `cali-to-wl-dispatch`: Các chain phân phối gói tin từ workload (Pod) đi ra hoặc đi vào.
> * Và đặc biệt là các chain có dạng `cali-fw-<hash>` (Egress - đi ra khỏi Pod) và `cali-tw-<hash>` (Ingress - đi vào Pod).
>
> (Chạy lệnh xem cali-FORWARD)
> Hãy xem cách Calico phân phối gói tin tại chain `cali-FORWARD`. Nhìn vào đây, các bạn sẽ thấy mọi gói tin đi qua (forward) trên card mạng vật lý đều sẽ bị nhảy (jump) vào các chain điều phối của Calico.
>
> (Chạy lệnh xem chi tiết cali-tw-<hash>)
> Khi tôi drill sâu vào chain `cali-tw` hướng tới Pod frontend của chúng ta, các bạn sẽ thấy các dòng luật cụ thể:
> * Nếu gói tin đi từ IP của Pod `backend` thì `ACCEPT` (cho phép đi qua).
> * Còn các gói tin khác không khớp luật thì sẽ bị `DROP` hoặc `MARK` để hủy bỏ ở cuối chain.
>
> Qua đây các bạn có thể tự tin khẳng định: NetworkPolicy trong Kubernetes không phải là cái gì đó quá trừu tượng, nó đơn giản là các dòng luật `iptables` vô cùng thực tế và đanh thép ngay ở tầng Kernel của hệ điều hành Linux!"*

---

## 🔬 Thí nghiệm 3: Cài và dùng calicoctl

### 🖥️ Hành động trên màn hình:
*   Mở Terminal đăng nhập vào `controlplane`.
*   Thực hiện chạy lệnh `curl` để tải binary `calicoctl` phiên bản `v3.32.0`.
*   Phân quyền, di chuyển vào `/usr/local/bin` và chạy lần loạt các lệnh truy vấn endpoints, ippool, và BGP status.

### 🗣️ Lời nói của người dẫn (Speaker Script):
> *"Khi vận hành Calico trong môi trường thực tế, nếu chỉ dùng `kubectl` thì chúng ta sẽ rất khó xem được các thực thể mạng chuyên sâu của CNI. Đó là lý do tại sao chúng ta bắt buộc phải cài đặt công cụ chuyên dụng gọi là `calicoctl`.
>
> (Chạy lệnh curl tải calicoctl)
> Tôi sẽ tải trực tiếp phiên bản `v3.32.0` đồng bộ hoàn toàn với bản Calico đang chạy trong cụm lab của mình.
>
> (Chạy lệnh calicoctl get workloadendpoint)
> Lệnh đầu tiên và cực kỳ hữu ích là `calicoctl get workloadendpoint`. Lệnh này giúp chúng ta xem danh sách các Pod đang được Calico gán mạng. Các bạn có thể thấy rõ: Tên Pod là gì, nằm ở Node nào, địa chỉ IP ảo được cấp là bao nhiêu và cả tên của card mạng ảo tương ứng trên Host (dạng `cali...`). Điều này cực kỳ hữu ích khi cần dùng tcpdump để bắt gói tin.
>
> (Chạy lệnh calicoctl get ippool)
> Lệnh thứ hai: `ippool`. Nó cho thấy dải IP `10.244.0.0/16` mà chúng ta cấu hình ban đầu đang hoạt động với cơ chế đóng gói `VXLANCrossSubnet`.
>
> (Chạy lệnh calicoctl node status)
> Và đây là lệnh quan trọng nhất để kiểm tra sức khỏe của BGP: `calicoctl node status`. Các bạn nhìn xem, tiến trình BIRD đang chạy rất tốt. Nó hiển thị kết nối BGP Peer thành công với các Node còn lại (`worker1`, `worker2`), trạng thái là `Established` (đã thiết lập kết nối). Điều này có nghĩa là các Node đang liên tục trao đổi bảng định tuyến L3 với nhau một cách hoàn hảo!"*

---

## 🔬 Thí nghiệm 4: Kiểm tra Typha

### 🖥️ Hành động trên màn hình:
*   Chạy lệnh xem các Pod trong namespace `calico-system` để tìm Pod `calico-typha`.
*   Xem logs của Typha để kiểm tra số lượng connection.
*   Xem cấu hình cài đặt của Tigera Operator để giải thích điều kiện kích hoạt Typha.

### 🗣️ Lời nói của người dẫn (Speaker Script):
> *"Thí nghiệm cuối cùng của chúng ta là về Typha - vị cứu tinh của các cụm Kubernetes quy mô lớn.
>
> (Chạy lệnh get pods)
> Trong namespace `calico-system`, các bạn có thấy Pod nào tên là `calico-typha` không? Trong cụm Lab 3 nodes của chúng ta, tùy thuộc vào cấu hình mặc định của Operator, Pod Typha có thể đang chạy với 1 replica hoặc có thể không được kích hoạt (0 replicas).
>
> (Chạy lệnh xem cấu hình installation)
> Chúng ta hãy cùng xem cấu hình `installation` để xem Operator quy định thế nào về việc triển khai Typha.
>
> (Chỉ tay vào cấu hình typhaDeployment)
> Mặc định, Tigera Operator cực kỳ thông minh: nó sẽ chỉ tự động triển khai và tăng số lượng bản sao Typha khi số lượng Node trong cụm của bạn vượt quá con số 3. Đối với cụm nhỏ 3 nodes, việc bắt Felix kết nối qua Typha là không thực sự cần thiết, các Felix kết nối thẳng tới API Server vẫn đảm bảo hiệu năng tối đa mà lại tiết kiệm được tài nguyên RAM cho máy ảo.
>
> Nhưng khi bạn vận hành hệ thống thực tế với hàng trăm Node, Typha sẽ tự động xuất hiện để gánh vác toàn bộ lượng truy cập này, giữ cho API Server của cụm K8s luôn ở trạng thái an toàn nhất!"*

---

## 🎬 Lời kết thúc Lab (Lab Outro)

### 🗣️ Lời nói của người dẫn (Speaker Script):
> *"Như vậy là chúng ta đã hoàn thành xuất sắc 4 thí nghiệm thực chiến cực kỳ chuyên sâu của Tập 10. Chúng ta đã giải phẫu thành công bộ máy hoạt động của Calico, hiểu rõ vai trò của Felix, BIRD và Typha trong thực tế.
>
> Ở tập tiếp theo, chúng ta sẽ bước vào một trận chiến hiệu năng cực kỳ gay cấn: **iptables vs eBPF Dataplane**. Khi nào chúng ta nên nâng cấp cụm Calico lên chạy eBPF, và sự đánh đổi về mặt tài nguyên là gì?
>
> Đừng quên nhấn Like, Đăng ký kênh và bấm chuông thông báo để không bỏ lỡ các tập học mạng thực chiến tiếp theo. Xin chào và hẹn gặp lại các bạn!"*
