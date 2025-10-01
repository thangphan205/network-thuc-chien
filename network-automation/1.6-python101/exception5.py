try:
    # Mã không gây lỗi
    a = 10
    b = 0
    result = a / b
except ZeroDivisionError:
    print("Lỗi chia cho 0!")
else:
    # Chỉ chạy khi không có lỗi
    print(f"Kết quả là: {result}")
