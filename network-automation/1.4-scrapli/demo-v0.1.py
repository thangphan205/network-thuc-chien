from scrapli import Scrapli
import os

# Tạo thư mục backup nếu chưa có
backup_dir = "backup-files"
os.makedirs(backup_dir, exist_ok=True)

# Danh sách IP các thiết bị Cisco IOS
cisco_ips = [f"192.168.11.{i}" for i in range(11, 16)]

for ip in cisco_ips:
    device = {
        "host": ip,
        "auth_username": "backup_user",
        "auth_password": "Poothe0uR3Ohziox6mos",
        "auth_strict_key": False,
        "platform": "cisco_iosxe",
    }
    try:
        print(f"Đang kết nối tới thiết bị {ip} ...")
        conn = Scrapli(**device)
        conn.open()
        response = conn.send_command("show running-config")
        filename = f"{backup_dir}/{ip.replace('.', '_')}-config.txt"
        with open(filename, "w") as f:
            f.write(response.result)
        conn.close()
        print(f"Đã backup cấu hình thiết bị {ip} vào file {filename}")
    except Exception as e:
        print(f"Lỗi với thiết bị {ip}: {e}")

print("--- Script completed successfully ---")
