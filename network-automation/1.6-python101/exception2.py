try:
    # Đoạn mã có thể gây ra lỗi
    print(10 / 0)
except ZeroDivisionError:
    # Đoạn mã được thực thi nếu lỗi ZeroDivisionError xảy ra
    print("Không thể chia cho số 0!")
