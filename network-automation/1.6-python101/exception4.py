try:
    # Đoạn mã có thể gây ra lỗi
    # Ví dụ: Mở một tệp không tồn tại
    with open("file_khong_ton_tai.txt", "r") as f:
        content = f.read()
except Exception as eo:
    # 'Exception' là lớp cơ sở của hầu hết các lỗi
    # 'as e' lưu đối tượng lỗi vào biến e để bạn có thể xem chi tiết
    print(f"Đã xảy ra một lỗi: {eo}")
