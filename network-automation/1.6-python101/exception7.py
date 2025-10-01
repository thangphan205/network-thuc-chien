try:
    # Mở một tệp tin để ghi
    f = open("my_file.txt", "w")
    f.write("Xin chào, đây là nội dung của tệp tin! ghi lần 2")
except IOError as e:
    # Xử lý lỗi nếu không thể mở hoặc ghi tệp
    print(f"Lỗi: Không thể truy cập tệp tin. Chi tiết: {e}")
else:
    # Đoạn mã này chỉ chạy khi không có lỗi IO
    print("Ghi dữ liệu vào tệp tin thành công.")
finally:
    # Đoạn mã này luôn chạy, đảm bảo tệp tin được đóng
    if "f" in locals() and not f.closed:
        f.close()
    print("Tệp tin đã được đóng.")
