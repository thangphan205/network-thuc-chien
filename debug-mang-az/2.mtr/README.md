# 🛠 MTR (My Traceroute) - Khám bệnh mạng toàn diện

Khi hệ thống mạng bị chậm hoặc chập chờn, kỹ sư mạng thường dùng 2 lệnh kinh điển: `ping` (để kiểm tra kết nối điểm-điểm) và `traceroute` (để xem đường đi của gói tin). 

Tuy nhiên, **MTR** (trước đây là Matt's Traceroute, nay gọi là My Traceroute) đã ra đời để kết hợp sức mạnh của cả hai công cụ này thành một giao diện thời gian thực (real-time) duy nhất, liên tục và vô cùng mạnh mẽ.

---

## 🥊 So sánh: MTR vs Traceroute

| Tiêu chí | `traceroute` | `mtr` |
| :--- | :--- | :--- |
| **Cách hoạt động** | Gửi một chuỗi gói tin với TTL tăng dần, lấy kết quả 1 lần cho mỗi trạm rồi dừng lại. | Gửi các gói tin liên tục (như `ping`) kết hợp với kỹ thuật khám phá trạm (như `traceroute`) và cập nhật màn hình mỗi giây. |
| **Khả năng phát hiện chập chờn** | **Rất Kém.** Vì chỉ quét qua 1 lần nên dễ dàng bỏ sót các lỗi rớt gói (packet loss) xảy ra ngẫu nhiên hoặc theo chu kỳ. | **Tuyệt Vời.** Thống kê chính xác tỷ lệ % Packet Loss và sự dao động độ trễ (Jitter) theo thời gian thực. |
| **Giao diện** | Văn bản tĩnh (Static text), in ra từng dòng. | Bảng điều khiển (Dashboard) thời gian thực hoặc xuất Báo cáo (Report mode). |
| **Ứng dụng chính** | Xác định nhanh đường đi (Routing path). | Tìm kiếm "điểm nghẽn" (bottleneck), chẩn đoán độ ổn định của kết nối trong thời gian dài. |

> **💡 Tóm lại:** Nếu `traceroute` giống như bạn **chụp một bức ảnh** tĩnh, thì `mtr` giống như bạn đang **quay một đoạn video** về đường truyền mạng của mình.

---

## 🚀 Cài đặt

**Ubuntu / Debian:**
```bash
sudo apt update
sudo apt install mtr
```

**CentOS / RHEL:**
```bash
sudo yum install mtr
```

**macOS (Homebrew):**
```bash
brew install mtr
# Lưu ý: Trên macOS, lệnh mtr yêu cầu quyền root nên bạn cần chạy sudo mtr
```

---

## 📖 Hướng dẫn sử dụng (Cheatsheet)

### 1. Sử dụng cơ bản (Giao diện tương tác)
Lệnh cơ bản nhất, mở ra một bảng điều khiển tương tác cập nhật mỗi giây:
```bash
mtr google.com
```

### 2. Chế độ xuất Báo cáo (Report Mode)
Cực kỳ hữu ích khi bạn muốn lấy kết quả dạng tĩnh để gửi cho bộ phận hỗ trợ (NOC, ISP) hoặc đính kèm vào ticket. MTR sẽ tự động gửi 10 vòng gói tin (mặc định) và in ra bảng tổng kết rồi thoát.
```bash
mtr --report google.com
# Hoặc dùng cờ viết tắt:
mtr -r google.com

# Dùng -w (--report-wide) để tránh bị cắt ngắn tên hostname dài — quan trọng khi gửi cho NOC/ISP:
mtr -rw google.com
```

### 3. Tắt phân giải tên miền (Chống độ trễ hiển thị)
Đôi khi việc phân giải Reverse DNS cho từng bước nhảy (hop) mất rất nhiều thời gian và làm công cụ hiển thị chậm chạp. Hãy dùng cờ `-n` để hiển thị trực tiếp địa chỉ IP thay vì tên miền.
```bash
mtr -n google.com
```

### 4. Kiểm tra bằng TCP (Vượt Tường lửa)
Mặc định MTR dùng gói tin **ICMP** (giống Ping). Rất nhiều Firewall trên Internet chặn ICMP nhưng lại mở TCP (ví dụ Web Server mở port 80/443). Để kiểm tra đường đi thực tế của gói tin Web, ta ép MTR dùng TCP SYN packets:
```bash
# Kiểm tra đường đi đến port 443 (HTTPS)
sudo mtr --tcp --port 443 google.com

# Hoặc viết tắt:
sudo mtr -T -P 443 google.com
```

### 5. Tăng tần suất gửi (Thay đổi tần suất probe)
Nếu muốn phát hiện sự cố cực nhanh bằng cách gửi 0.1 giây / gói (nhanh hơn mặc định là 1 giây).
```bash
sudo mtr -i 0.1 google.com
```

---

## 🔍 Cách đọc chỉ số MTR

Khi chạy MTR, bạn sẽ thấy các cột hiển thị:
- **Host:** Tên miền hoặc IP của thiết bị trung chuyển (Router).
- **Loss%:** Tỷ lệ phần trăm gói tin bị rớt ở trạm đó. *(Lưu ý: Nếu một trạm có Loss% cao (ví dụ 100%) nhưng các trạm phía sau Loss% vẫn là 0%, thì ĐÓ KHÔNG PHẢI LÀ LỖI. Đó là do Router đó chủ động Rate-Limit (thả trôi) gói ICMP gửi đến CPU của nó).*
- **Snt:** Số lượng gói tin (Sent) đã gửi.
- **Last:** Độ trễ (Ping/Latency) của gói tin gần nhất.
- **Avg:** Độ trễ trung bình.
- **Best / Wrst:** Độ trễ tốt nhất / tệ nhất.
- **StDev:** Độ lệch chuẩn (Standard Deviation). **Đây là chỉ số quan trọng!** Số này càng cao nghĩa là kết nối càng chập chờn (Jitter lớn), ping lúc cao lúc thấp. Lý tưởng nhất là StDev gần 0.
- **`???`:** Hop không phản hồi gói ICMP (Router bỏ qua hoặc firewall chặn). **Không phải lỗi** nếu các hop phía sau vẫn hiển thị bình thường.

---

## 📈 Deep Dive: Chỉ số StDev (Standard Deviation) là gì?

Độ lệch chuẩn (**StDev**) trong MTR là chỉ số dùng để **xấp xỉ Jitter** (sự dao động/chập chờn của độ trễ mạng). Lưu ý: Jitter chuẩn (PDV - Packet Delay Variation) đo biến thiên giữa các gói *liên tiếp*, còn StDev đo mức phân tán so với trung bình (Avg) — hai khái niệm liên quan nhưng không hoàn toàn giống nhau.

### Cách MTR tính toán ngầm
MTR sử dụng công thức độ lệch chuẩn tiêu chuẩn trong thống kê cho mỗi trạm (hop):
1. **Tính Avg (Mean):** Lấy tổng thời gian phản hồi chia cho số gói đã nhận.
2. **Tính Phương sai (Variance):** Tính bình phương độ lệch của từng gói so với giá trị Avg, sau đó lấy trung bình cộng.
3. **Tính StDev:** Lấy căn bậc hai của Phương sai.

> **Công thức:** `σ = √[ Σ(x - μ)² / N ]`  
> Trong đó: `x` là ping từng gói, `μ` là Avg, `N` là số gói đã gửi.

### Ví dụ minh họa
*   **TH1: Ổn định (StDev thấp):** Ping là `20ms`, `21ms`, `19ms` -> **Avg: 20ms**, **StDev ≈ 0.8ms**. Mạng rất mượt.
*   **TH2: Chập chờn (StDev cao):** Ping là `20ms`, `150ms`, `18ms`, `200ms` -> **Avg: 97ms**, **StDev ≈ 81ms**. Đây là dấu hiệu của hiện tượng Jitter, cực kỳ có hại cho VoIP và Game online.

### Ngưỡng đánh giá StDev thực chiến

| StDev | Đánh giá | Ảnh hưởng thực tế |
| :--- | :--- | :--- |
| **< 5ms** | Tuyệt vời | Không ảnh hưởng gì |
| **5 – 15ms** | Tốt | Web, streaming, file transfer hoàn toàn OK |
| **15 – 30ms** | Biên giới | VoIP bắt đầu nghe tiếng rè, game có lag nhẹ |
| **30 – 50ms** | Cao | VoIP khó dùng, game online bị lag rõ |
| **> 50ms** | Nghiêm trọng | VoIP vỡ tiếng, game không chơi được |
| **> 100ms** | Rất nghiêm trọng | Có lỗi phần cứng hoặc link rõ ràng |

> **Chuẩn tham chiếu industry:**
> - **ITU-T G.114**: VoIP yêu cầu one-way delay < 150ms **và** jitter < 30ms
> - **RFC 3550 (RTP)**: Jitter > 50ms → VoIP bắt đầu không dùng được
> - **Gaming**: Jitter < 15ms để gameplay mượt

### Đọc StDev theo tỷ lệ — quan trọng hơn con số tuyệt đối

StDev phải đặt trong ngữ cảnh của Avg mới có ý nghĩa:

```
Avg = 200ms, StDev = 8ms  → StDev/Avg =  4%  → Rất ổn định ✅
                                                  (đường xuyên lục địa nhưng đều)

Avg = 10ms,  StDev = 8ms  → StDev/Avg = 80%  → Cực kỳ chập chờn ❌
                                                  (ping nhảy từ 2ms lên 18ms liên tục)
```

### Ý nghĩa thực chiến
Một đường truyền có **Ping cao nhưng ổn định** (StDev thấp) thường tốt hơn một đường truyền **Ping thấp nhưng trồi sụt thất thường** (StDev cao). Nếu bạn thấy StDev vọt lên ở một hop cụ thể, đó thường là dấu hiệu của việc Router bị quá tải CPU hoặc nghẽn hàng đợi (Queueing delay).
