import paramiko

hostname = "192.168.11.11"
username = "backup_user"
password = "Poothe0uR3Ohziox6mos"

command = "show ip int brief"

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
    stdin, stdout, stderr = ssh.exec_command(command)
    output = stdout.read().decode()
    print(output)
finally:
    ssh.close()
