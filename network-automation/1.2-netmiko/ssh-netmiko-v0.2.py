from netmiko import ConnectHandler

cisco1 = {
    "device_type": "cisco_ios",
    "host": "192.168.11.11",
    "username": "backup_user",
    "password": "Poothe0uR3Ohziox6mos",
}

net_connect = ConnectHandler(**cisco1)
command = "show run"
output = net_connect.send_command(command)
print(output)
net_connect.disconnect()
with open("backup-files/cisco1-config.txt", "w") as f:
    f.write(output)

print("--- Script completed successfully ---")
