from scrapli import Scrapli
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
            "host": ip,
            "auth_username": "backup_user",
            "auth_password": "Poothe0uR3Ohziox6mos",
            "auth_strict_key": False,
            "platform": "cisco_iosxe",
        }
    )

for ip in juniper_ips:
    devices.append(
        {
            "host": ip,
            "auth_username": "backup_user",
            "auth_password": "Poothe0uR3Ohziox6mos",
            "auth_strict_key": False,
            "platform": "juniper_junos",
        }
    )

for device in devices:
    ip = device["host"]
    try:
        print(f"Đang kết nối tới thiết bị {ip} ...")
        conn = Scrapli(**device)
        conn.open()

        response = None
        if device["platform"] == "cisco_iosxe":
            print(conn.get_prompt())
            response = conn.send_command("show running-config")
        elif device["platform"] == "juniper_junos":
            response = conn.send_command("show configuration | display set")
        else:
            response = None

        if response is not None:
            filename = f"{backup_dir}/{ip.replace('.', '_')}-config.txt"
            with open(filename, "w") as f:
                f.write(response.result)
            print(f"Đã backup cấu hình thiết bị {ip} vào file {filename}")
        conn.close()
    except Exception as e:
        print(f"Lỗi với thiết bị {ip}: {e}")

print("--- Script completed successfully ---")
