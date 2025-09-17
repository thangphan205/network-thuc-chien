from netmiko import ConnectHandler
import os

# Tạo thư mục backup nếu chưa có
backup_dir = "backup-files"
os.makedirs(backup_dir, exist_ok=True)

# Danh sách IP các thiết bị Cisco IOS
cisco_ips = [f"192.168.11.{i}" for i in range(11, 16)]
# Danh sách IP các thiết bị Juniper Junos
juniper_ips = [f"192.168.11.{i}" for i in range(21, 26)]

devices = []

for ip in cisco_ips:
    devices.append(
        {
            "device_type": "cisco_ios",
            "host": ip,
            "username": "backup_user",
            "password": "Poothe0uR3Ohziox6mos",
        }
    )

for ip in juniper_ips:
    devices.append(
        {
            "device_type": "juniper_junos",
            "host": ip,
            "username": "backup_user",
            "password": "Poothe0uR3Ohziox6mos",
        }
    )

for device in devices:
    ip = device["host"]
    try:
        print(f"Đang kết nối tới thiết bị {ip} ...")
        net_connect = ConnectHandler(**device)
        if device["device_type"] == "cisco_ios":
            output = net_connect.send_command("show running-config")
        elif device["device_type"] == "juniper_junos":
            output = net_connect.send_command("show configuration | display set")
        else:
            output = "Không hỗ trợ loại thiết bị này."
        filename = f"{backup_dir}/{ip.replace('.', '_')}-config.txt"
        with open(filename, "w") as f:
            f.write(output)
        net_connect.disconnect()
        print(f"Đã backup cấu hình thiết bị {ip} vào file {filename}")
    except Exception as e:
        print(f"Lỗi với thiết bị {ip}: {e}")

print("--- Script completed successfully ---")
