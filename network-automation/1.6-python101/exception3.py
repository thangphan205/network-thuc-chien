try:
    # Đoạn mã có thể gây ra lỗi
    number = int(input("Nhập một số: "))
    result = 10 / number
    print(result)
except:
    print("Đã có lỗi gì đó xảy ra.")
# except ValueError:
#     # Xử lý lỗi nếu người dùng nhập chữ thay vì số
#     print("Bạn đã nhập không phải là số hợp lệ.")
# except ZeroDivisionError:
#     # Xử lý lỗi nếu người dùng nhập số 0
#     print("Không thể chia cho số 0!")


print(5 + 5)
