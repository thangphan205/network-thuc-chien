# 📋 Mẫu Biên Bản Hậu Sự Cố (Post-mortem)

> Bước 5 của quy trình bắt bệnh không dừng ở "chữa xong". Một kỹ sư giỏi luôn viết lại
> **bệnh án** để lần sau cả team không mắc lại. Copy mẫu này cho mỗi sự cố thật.

---

## 1. Tóm tắt (TL;DR)
*Một đoạn 2–3 câu: chuyện gì xảy ra, ảnh hưởng ai, đã xử lý thế nào.*

## 2. Mức độ ảnh hưởng
| Hạng mục | Chi tiết |
|---|---|
| Thời gian bắt đầu | `YYYY-MM-DD HH:MM` |
| Thời gian phát hiện | |
| Thời gian khôi phục | |
| Tổng thời gian downtime | |
| Dịch vụ / khách hàng bị ảnh hưởng | |

## 3. Dòng thời gian (Timeline)
| Thời điểm | Sự việc / Hành động |
|---|---|
| `HH:MM` | Cảnh báo đầu tiên / người dùng báo lỗi |
| `HH:MM` | Bắt đầu điều tra (bước nào của quy trình?) |
| `HH:MM` | Xác định root cause |
| `HH:MM` | Áp dụng cách chữa |
| `HH:MM` | Xác nhận hệ thống hồi phục |

## 4. Chẩn đoán theo tầng (Bắt mạch)
*Ghi lại đúng bằng chứng đã thu thập ở từng tầng — không phải suy đoán:*

- **L2/L3:** `ping`, `ip route`, `ip neigh` cho kết quả gì?
- **L4:** `ss -tulpn`, `nc -zvw`, `iptables -L` cho thấy gì?
- **L5/6:** `openssl s_client`, `date` (nếu liên quan TLS)?
- **L7:** `dig`, `curl -v`, mã HTTP?
- **Gói tin (Wireshark/tcpdump):** cờ bất thường (SYN Retransmission, RST, ICMP Type 3)?

## 5. Nguyên nhân gốc (Root Cause)
*Chốt chính xác. Phân biệt: nguyên nhân trực tiếp vs nguyên nhân sâu xa (tại sao lỗi đó lọt được vào production).*

## 6. Cách chữa (đã làm)
*Lệnh/thao tác cụ thể đã dùng để khôi phục.*

## 7. Phòng ngừa tái diễn (Action items)
| Việc cần làm | Người phụ trách | Hạn |
|---|---|---|
| Thêm alert/monitoring cho triệu chứng này | | |
| Sửa cấu hình / thêm kiểm thử tự động | | |
| Cập nhật runbook / tài liệu | | |

## 8. Bài học rút ra
*Điều gì làm tốt? Điều gì may mắn? Điều gì cần cải thiện trong lần bắt bệnh sau?*
