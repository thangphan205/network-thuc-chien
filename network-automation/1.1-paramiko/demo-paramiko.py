import paramiko
import time

# Thông tin thiết bị
HOST = "192.168.11.11"  # Thay bằng địa chỉ IP thiết bị của bạn
USERNAME = "backup_user"  # Thay bằng username của bạn
PASSWORD = "Poothe0uR3Ohziox6mos"  # Thay bằng password của bạn

try:
    # Tạo SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        HOST,
        username=USERNAME,
        password=PASSWORD,
        look_for_keys=False,
        allow_agent=False,
    )

    # Mở phiên shell
    remote_conn = ssh.invoke_shell()
    time.sleep(1)
    remote_conn.send("enable\n")
    time.sleep(1)
    # Nếu có enable password thì gửi ở đây: remote_conn.send("enable_pass\n")
    remote_conn.send("terminal length 0\n")
    time.sleep(1)
    remote_conn.send("show version\n")
    time.sleep(2)

    # Nhận kết quả
    output = remote_conn.recv(65535).decode("utf-8")
    print(output)

finally:
    if "ssh" in locals():
        ssh.close()
