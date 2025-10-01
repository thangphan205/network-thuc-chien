try:
    f = open("file_da_co.txt", "w")
    f.write("Xin chào!")
except Exception as e:
    print(f"Đã xảy ra lỗi: {e}")
finally:
    # Luôn luôn đóng tệp tin, bất kể có lỗi hay không
    f.close()
    print("Tệp đã được đóng.")
