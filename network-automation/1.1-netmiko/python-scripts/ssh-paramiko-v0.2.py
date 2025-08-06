import paramiko
import time

hostname = "192.168.11.11"
username = "backup_user"
password = "Poothe0uR3Ohziox6mos"

# Interface configuration parameters
interface = "Ethernet0/1"
ip_address = "192.168.100.10"
subnet_mask = "255.255.255.0"

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    ssh.connect(
        hostname,
        username=username,
        password=password,
        look_for_keys=False,
        allow_agent=False,
    )
    remote_conn = ssh.invoke_shell()
    time.sleep(1)
    remote_conn.send("enable\n")
    time.sleep(1)
    # If enable password is required, send it here: remote_conn.send("your_enable_password\n")
    remote_conn.send("configure terminal\n")
    time.sleep(1)
    remote_conn.send(f"interface {interface}\n")
    time.sleep(1)
    remote_conn.send(f"ip address {ip_address} {subnet_mask}\n")
    time.sleep(1)
    remote_conn.send("no shutdown\n")
    time.sleep(1)
    remote_conn.send("end\n")
    time.sleep(1)
    remote_conn.send("write memory\n")
    time.sleep(2)
    output = remote_conn.recv(65535).decode()
    print(output)
finally:
    ssh.close()
