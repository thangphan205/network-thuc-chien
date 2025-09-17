from netmiko import ConnectHandler
import os

# Tạo thư mục backup nếu chưa có
backup_dir = "backup-files"
os.makedirs(backup_dir, exist_ok=True)

# Danh sách IP các thiết bị Cisco IOS
device_ips = [f"192.168.11.{i}" for i in range(11, 16)]

for ip in device_ips:
    cisco_device = {
        "device_type": "cisco_ios",
        "host": ip,
        "username": "backup_user",
        "password": "Poothe0uR3Ohziox6mos",
    }
    try:
        print(f"Đang kết nối tới thiết bị {ip} ...")
        net_connect = ConnectHandler(**cisco_device)
        output = net_connect.send_command("show running-config")
        filename = f"{backup_dir}/{ip.replace('.', '_')}-config.txt"
        with open(filename, "w") as f:
            f.write(output)
        net_connect.disconnect()
        print(f"Đã backup cấu hình thiết bị {ip} vào file {filename}")
    except Exception as e:
        print(f"Lỗi với thiết bị {ip}: {e}")

print("--- Script completed successfully ---")
