from netmiko import ConnectHandler

cisco1 = {
    "device_type": "cisco_ios",
    "host": "192.168.11.11",
    "username": "backup_user",
    "password": "Poothe0uR3Ohziox6mos",
}

net_connect = ConnectHandler(**cisco1)
command = "show ip interface brief"
output = net_connect.send_command(command)
print(output)
net_connect.disconnect()

print("--- Script completed successfully ---")
